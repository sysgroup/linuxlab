# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/storage.tf  -  dyski maszyn / VM storage
# ============================================================================

# 1) DYSK SYSTEMOWY VM / VM OS DISK - warstwa CoW na golden image (z base/).
# 🎓 EGZAMIN: `for_each` po MAPIE => adres libvirt_volume.vm_disk["deb13"], a each.key
#   = "deb13", each.value = cały obiekt VM. Różnica vs `count`: usunięcie wpisu ze
#   środka mapy NIE przesuwa pozostałych (klucze stabilne); przy `count` indeksy się
#   przesuwają i powodują niepotrzebne przebudowy. Preferuj for_each dla nazwanych zasobów.
resource "libvirt_volume" "vm_disk" {
  for_each = local.active_vms

  name = "${each.key}.img"
  pool = var.vm_pool
  # PL: KLUCZOWE: provider z `file=` w domenie deklaruje dysk jako <driver type='raw'>.
  #     Dlatego w trybie copy robimy dysk FAKTYCZNIE raw (konwersja z qcow2 golden),
  #     by format się zgadzał - inaczej qemu czyta nagłówek qcow2 jako MBR i SeaBIOS
  #     mówi "not a bootable disk". cow zostaje qcow2 (wymaga go backing chain).
  # EN: CRITICAL: with `file=` the provider declares the domain disk as type='raw'.
  #     So in copy mode the volume must be REALLY raw (converted from the qcow2
  #     golden) to match - otherwise qemu reads the qcow2 header as the MBR and boot
  #     fails. cow stays qcow2 (needed for the backing chain).
  format = var.disk_strategy == "copy" ? "raw" : "qcow2"

  base_volume_id = var.disk_strategy == "cow" ? var.base_volume_ids[each.value.distro] : null
  source         = var.disk_strategy == "copy" ? var.base_volume_ids[each.value.distro] : null

  # 🎓 EGZAMIN / pułapka providera: 'source' i 'size' WYKLUCZAJĄ SIĘ w
  #   dmacvicar/libvirt. Dlatego w trybie 'copy' size=null, a osobny terraform_data
  #   poniżej powiększa gotową kopię przed uruchomieniem domeny.
  size = var.disk_strategy == "cow" ? each.value.disk_gib * 1024 * 1024 * 1024 : null
}

# W trybie copy provider nie pozwala ustawić size razem z source. Po skopiowaniu
# golden image powiększamy więc wolumen przez libvirt. `input.volume_id` jest potem
# używane przez domenę, co tworzy zależność: resize kończy się przed pierwszym bootem,
# a cloud-init/growpart rozszerza partycję i system plików.
resource "terraform_data" "vm_disk_resize" {
  for_each = var.disk_strategy == "copy" ? local.active_vms : {}

  input = {
    volume_id = libvirt_volume.vm_disk[each.key].id
    size_gib  = each.value.disk_gib
  }

  triggers_replace = {
    volume_id = libvirt_volume.vm_disk[each.key].id
    size_gib  = each.value.disk_gib
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      target=$(( ${each.value.disk_gib} * 1024 * 1024 * 1024 ))
      current=$(virsh -c ${var.libvirt_uri} vol-info --bytes --pool ${var.vm_pool} ${libvirt_volume.vm_disk[each.key].name} | awk '/Capacity/ {print $2}')
      if [ "$current" -lt "$target" ]; then
        echo "${libvirt_volume.vm_disk[each.key].name}: resize $current -> $target B"
        virsh -c ${var.libvirt_uri} vol-resize --pool ${var.vm_pool} ${libvirt_volume.vm_disk[each.key].name} "$target"
      else
        echo "${libvirt_volume.vm_disk[each.key].name}: $current B >= $target B (skip)"
      fi
    EOT
  }
}

# 2) DYSKI DODATKOWE / EXTRA DATA DISKS - tylko dla VM z extra_disks_gib (PBS).
resource "libvirt_volume" "extra_disk" {
  for_each = local.extra_disks

  name   = "${each.key}.qcow2"
  pool   = var.vm_pool
  format = "qcow2"
  size   = each.value.size_gib * 1024 * 1024 * 1024
}
