# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  infra/outputs.tf  -  re-eksport outputów modułu / re-export module outputs
# ============================================================================

output "vms_by_group" {
  description = "Mapa grupa -> lista nazw VM."
  value       = module.vms.vms_by_group
}

output "vms" {
  description = "Podsumowanie maszyn infra."
  value       = module.vms.vms
}

output "ssh" {
  description = "Komendy SSH per VM."
  value       = module.vms.ssh
}

output "desktop_hint" {
  description = "Jak otworzyć pulpit graficzny (SPICE) - dot. kdev."
  value       = "virt-viewer --connect ${var.libvirt_uri} kdev"
}
