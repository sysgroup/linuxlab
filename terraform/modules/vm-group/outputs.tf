# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/outputs.tf  -  wyjścia modułu / module outputs
# ----------------------------------------------------------------------------
#  PL: Root (testboxes/ infra/) re-eksportuje te wartości, a Makefile czyta je
#      przez `terraform output -json` (operacje na grupach, IP, SSH).
#  EN: The root (testboxes/ infra/) re-exports these; the Makefile reads them
#      via `terraform output -json` (group ops, IPs, SSH).
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 5/8): `output` w MODULE = jego wynik publiczny. Root czyta
#   go jako module.vms.<output> i re-eksportuje własnym `output`. `vms` używa
#   FOR-EXPRESSION po libvirt_domain.vm (splat-podobny przelot po instancjach
#   for_each), a `try(...)` zwraca "" gdy brak IP (np. running=false). To wzorzec
#   modułu jako komponentu wielokrotnego użytku.
# ============================================================================

output "vms_by_group" {
  description = "Mapa grupa -> lista nazw VM."
  value       = local.vms_by_group
}

output "vms" {
  description = "Podsumowanie maszyn: grupa, distro, sieć, running, IP."
  value = {
    for k, d in libvirt_domain.vm : k => {
      group   = local.active_vms[k].group
      distro  = local.active_vms[k].distro
      network = local.active_vms[k].network
      running = local.active_vms[k].running
      ip      = try(d.network_interface[0].addresses[0], "")
    }
  }
}

output "ssh" {
  description = "Komendy SSH per VM."
  value = {
    for k, d in libvirt_domain.vm : k =>
    "ssh ${var.username}@${try(d.network_interface[0].addresses[0], "<IP? virsh -c ${var.libvirt_uri} domifaddr ${k}>")}"
  }
}
