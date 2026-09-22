# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/network.tf  -  współdzielona sieć laboratoryjna / shared lab network
# ----------------------------------------------------------------------------
#  PL: Sieć NAT dla maszyn testowych. Sieć libvirt "default" używana przez
#      maszyny infra istnieje poza tym rootem i nie jest tutaj zarządzana.
#  EN: NAT network for test boxes. The libvirt "default" network used by infra
#      machines exists outside this root and is not managed here.
# ============================================================================

resource "libvirt_network" "lab" {
  name      = var.lab_network_name
  mode      = "nat"
  addresses = [var.lab_network_cidr]
  domain    = var.lab_network_domain

  dhcp { enabled = true }
  dns { enabled = true }

  autostart = true
}
