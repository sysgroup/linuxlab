# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/outputs.tf  -  "API" warstwy bazowej / base layer "API"
# ----------------------------------------------------------------------------
#  PL: Te wartości czytają roots VM przez terraform_remote_state. NIE oznaczamy
#      ich jako sensitive - to ID i nazwy, nie sekrety.
#  EN: Read by the VM roots via terraform_remote_state. Not sensitive - these are
#      IDs and names, not secrets.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 8 + 7): OUTPUT VALUE = wartość zwracana po apply, widoczna
#   przez `terraform output [-json|-raw]`. To JEDYNA część stanu warstwy `base/`,
#   którą zobaczą inne rooty przez terraform_remote_state. `base_volume_ids` używa
#   FOR-EXPRESSION { for k,v in ... : k => v.id } do zbudowania mapy distro->ID.
#   Output z `sensitive = true` byłby ukryty w `terraform output` (trzeba -raw/-json).
# ============================================================================

# PL: Mapa distro -> ID golden image. To wstrzykuje root do modułu jako
#     base_volume_ids (vm_disk robi z tego warstwę CoW).
# EN: Map distro -> golden-image volume ID, fed by the root into the module.
output "base_volume_ids" {
  description = "Mapa distro -> ID woluminu golden image."
  value       = { for k, v in libvirt_volume.base : k => v.id }
}

output "lab_network_name" {
  description = "Nazwa sieci lab (root mapuje na nią VM z network='lab')."
  value       = libvirt_network.lab.name
}

output "golden_pool_name" {
  description = "Nazwa puli golden."
  value       = libvirt_pool.golden.name
}

output "lab_network" {
  description = "Sieć laboratoryjna (CIDR i domena)."
  value       = "${libvirt_network.lab.name}: ${var.lab_network_cidr} (.lab DNS: *.${var.lab_network_domain})"
}

output "built_distros" {
  description = "Które golden images zbudowano w tej warstwie."
  value       = sort(local.distros_to_build)
}
