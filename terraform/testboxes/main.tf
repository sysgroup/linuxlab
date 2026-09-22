# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  testboxes/main.tf  -  remote_state(base) + wywołanie modułu vm-group
# ----------------------------------------------------------------------------
#  PL: 1) Czytamy stan warstwy base/ (golden images + sieć lab) - to MUSI być
#         już zbudowane (`make base` / apply w base/).
#      2) Wołamy wspólny moduł, podając mapę testboxów i ID golden images.
#  EN: 1) Read the base/ layer state (golden images + lab network) - it MUST be
#         applied first. 2) Call the shared module with the test-box map.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN: trzy kluczowe konstrukcje na egzaminie w jednym pliku - LOCAL +
#   funkcje (file/pathexpand/trimspace), DATA SOURCE (terraform_remote_state, tylko
#   odczyt), oraz MODULE block (source/inputs). Patrz tagi niżej.
# ============================================================================

locals {
  # 🎓 EGZAMIN (Objective 8 - functions): file() czyta plik, pathexpand() rozwija ~,
  #   trimspace() ucina biały znak. Zagnieżdżanie funkcji = composition.
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# PL: Most do osobnego stanu warstwy base/. Backend lokalny => czytamy plik
#     ../base/terraform.tfstate. base/ MUSI być wcześniej `apply`.
# EN: Bridge to the base/ layer's separate state. Local backend => read the
#     ../base/terraform.tfstate file. base/ MUST be applied first.
# 🎓 EGZAMIN (Objective 8 - data sources / Objective 7 - state): `data` CZYTA, nie
#   tworzy (kontrast: `resource` zarządza zasobem). terraform_remote_state widzi
#   TYLKO outputy innego roota. Odwołanie: data.terraform_remote_state.base.outputs.X.
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = var.base_state_path
  }
}

# 🎓 EGZAMIN (Objective 5 - modules): MODULE block woła child module. `source` =
#   skąd (tu ścieżka lokalna ../; może być Registry "ns/name/provider" albo git).
#   Argumenty = INPUTY (var w module). Wyjścia czytasz jako module.vms.<output>.
#   UWAGA: `version` działa tylko dla modułów z Registry, nie dla ścieżek lokalnych.
#   Po dodaniu/zmianie modułu trzeba `terraform init`.
module "vms" {
  source = "../modules/vm-group"

  vms            = var.vms
  only_groups    = var.only_groups
  vm_pool        = var.vm_pool
  disk_strategy  = var.disk_strategy
  wait_for_lease = var.wait_for_lease
  machine        = var.machine
  firmware       = var.firmware

  base_volume_ids  = data.terraform_remote_state.base.outputs.base_volume_ids
  lab_network_name = data.terraform_remote_state.base.outputs.lab_network_name

  lab_network_domain = var.lab_network_domain
  username           = var.username
  user_password      = var.user_password
  ssh_public_key     = local.ssh_public_key
  libvirt_uri        = var.libvirt_uri
}
