# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  infra/main.tf  -  remote_state(base) + wywołanie modułu vm-group
# ----------------------------------------------------------------------------
#  PL: Jak testboxes/main.tf, tylko z mapą maszyn usługowych. Warstwa base/
#      (golden images + sieć lab) musi być już zbudowana.
#  EN: Like testboxes/main.tf but with the service-machine map. The base/ layer
#      must be applied first.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN: budowa identyczna jak testboxes/main.tf (local + data source
#   terraform_remote_state + module block) - szczegółowe tagi egzaminacyjne są
#   tam. Tu różni się tylko mapa `vms` (maszyny usługowe, sieć "default").
# ============================================================================

locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = var.base_state_path
  }
}

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
