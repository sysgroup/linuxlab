# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  testboxes/outputs.tf  -  re-eksport outputów modułu / re-export module outputs
# ----------------------------------------------------------------------------
#  PL: Makefile czyta `vms_by_group`, `vms`, `ssh` przez `terraform output -json`.
#  EN: The Makefile reads these via `terraform output -json`.
# ============================================================================

output "vms_by_group" {
  description = "Mapa grupa -> lista nazw VM."
  value       = module.vms.vms_by_group
}

output "vms" {
  description = "Podsumowanie maszyn testowych."
  value       = module.vms.vms
}

output "ssh" {
  description = "Komendy SSH per VM."
  value       = module.vms.ssh
}

output "lab_network" {
  description = "Sieć laboratoryjna (z warstwy base/)."
  value       = data.terraform_remote_state.base.outputs.lab_network
}
