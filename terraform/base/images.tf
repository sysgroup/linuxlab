# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/images.tf  -  pula golden + obrazy bazowe
# ----------------------------------------------------------------------------
#  PL: Obrazy bazowe współdzielone przez rooty VM przez terraform_remote_state.
#      Sieć laboratoryjna jest zdefiniowana osobno w network.tf.
#  EN: Base images shared by VM roots through terraform_remote_state. The lab
#      network is defined separately in network.tf.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 8): w tym pliku masz `resource` (zarządza/tworzy zasób -
#   w odróżnieniu od `data`, które tylko czyta), local value, conditional (ternary),
#   meta-argument `for_each`, funkcje `length()/keys()/toset()` oraz IMPLICIT
#   DEPENDENCY (libvirt_volume.base odwołuje się do libvirt_pool.golden.name, więc
#   pula powstaje przed obrazami - bez żadnego depends_on).
# ============================================================================

locals {
  # PL: Puste enabled_distros => wszystkie z katalogu. Inaczej tylko wskazane.
  # EN: Empty enabled_distros => the whole catalog. Otherwise only the listed.
  distros_to_build = length(var.enabled_distros) == 0 ? keys(var.distros) : var.enabled_distros

  # PL: Efektywny URL obrazu per distro. PRECEDENCJA (od najsilniejszej):
  #       1) image_overrides[distro]  - twardy pin na konkretny dzień,
  #       2) pinned_url               - gdy image_channel = "pinned",
  #       3) latest_url               - domyślnie (zawsze istnieje).
  #     To realizuje "latest vs pinned" z opisu w variables.tf.
  # EN: Effective image URL per distro. Precedence: per-distro override >
  #     pinned_url (when channel=pinned) > latest_url (always present).
  # 🎓 EGZAMIN: zagnieżdżony conditional (ternary) + for-expression budujący mapę.
  distro_url = { for k, d in var.distros : k => (
    contains(keys(var.image_overrides), k)
    ? var.image_overrides[k]
    : (var.image_channel == "pinned" && d.pinned_url != null ? d.pinned_url : d.latest_url)
  ) }
}

# Pula golden (typ "dir"). libvirtd jako root utworzy katalog.
resource "libvirt_pool" "golden" {
  name = var.golden_pool_name
  type = "dir"
  target {
    path = var.golden_pool_path
  }
}

# Golden image per dystrybucja - provider skopiuje/pobierze obraz z URL/ścieżki
# do puli 'golden'. Na tym hoście źródło jest RAW, bo domeny używają disk.file
# i provider/libvirt deklaruje potem dyski jako raw.
# 🎓 EGZAMIN: `for_each` po SECIE (toset) => adres instancji libvirt_volume.base["debian-12"],
#   a w środku each.key = "debian-12". Dla setu each.key == each.value.
resource "libvirt_volume" "base" {
  for_each = toset(local.distros_to_build)

  # Sufiks .qcow2 został dla zgodności ze stanem i istniejącymi ścieżkami; format
  # woluminu jest celowo RAW.
  name = "${each.key}-base.qcow2"
  # 🎓 EGZAMIN: odwołanie do .name TWORZY implicit dependency - pula przed obrazem.
  pool = libvirt_pool.golden.name
  # PL: URL wg kanału latest/pinned/override (local.distro_url, patrz wyżej).
  # EN: URL per the latest/pinned/override channel (see local.distro_url above).
  source = local.distro_url[each.key]
  format = "raw"
}

# ----------------------------------------------------------------------------
#  PL: Wymuszenie rozmiaru golden. Golden są RAW i mają `source`, a w
#      dmacvicar/libvirt (0.8.3) `size` i `source` WYKLUCZAJĄ SIĘ - więc nie da
#      się ustawić rozmiaru na samym woluminie. Robimy to PO utworzeniu:
#      idempotentny, TYLKO-W-GÓRĘ `virsh vol-resize` do golden_min_size_gib.
#      Kopie w testboxes (copy mode) dziedziczą rozmiar golden, a cloud-init
#      (growpart) rozszerza partycję root gościa przy pierwszym boocie.
#  EN: Enforce golden size. Goldens are RAW with `source`, and in the provider
#      (0.8.3) `size` and `source` are mutually exclusive - so the size can't be
#      set on the volume itself. We do it AFTER creation: an idempotent, grow-only
#      `virsh vol-resize` up to golden_min_size_gib. The testboxes copies (copy
#      mode) inherit the golden size; cloud-init growpart expands the guest root.
#  🎓 EGZAMIN: terraform_data + provisioner "local-exec". `triggers_replace` wiąże
#      re-run z ID golden - po odbudowie obrazu (nowe id) resize odpali ponownie.
# ----------------------------------------------------------------------------
resource "terraform_data" "golden_resize" {
  for_each = var.golden_min_size_gib > 0 ? libvirt_volume.base : {}

  triggers_replace = {
    volume_id = each.value.id
    size_gib  = var.golden_min_size_gib
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      target=$(( ${var.golden_min_size_gib} * 1024 * 1024 * 1024 ))
      cur=$(virsh -c ${var.libvirt_uri} vol-info --bytes --pool ${libvirt_pool.golden.name} ${each.value.name} | awk '/Capacity/ {print $2}')
      if [ "$cur" -lt "$target" ]; then
        echo "golden ${each.value.name}: resize $cur -> $target B"
        virsh -c ${var.libvirt_uri} vol-resize --pool ${libvirt_pool.golden.name} ${each.value.name} "$target"
      else
        echo "golden ${each.value.name}: $cur B >= $target B (skip)"
      fi
    EOT
  }
}
