# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/cloud-init.tf  -  konfiguracja startowa VM / VM bootstrap
# ============================================================================

resource "libvirt_cloudinit_disk" "vm_init" {
  for_each = local.active_vms

  # PL: NAZWA bez ".iso" celowo: provider widzi rozszerzenie .iso => podpina jako
  #     cdrom IDE (a q35 nie ma IDE). Z ".img" idzie jako DYSK virtio (vdb), a
  #     cloud-init i tak znajdzie seed po etykiecie 'cidata'. Treść to nadal ISO9660.
  # EN: Name WITHOUT ".iso" on purpose: the provider attaches .iso as an IDE cdrom
  #     (q35 has no IDE); ".img" => a virtio disk. cloud-init finds it by 'cidata' label.
  name = "${each.key}-seed.img"
  pool = var.vm_pool

  user_data = templatefile("${path.module}/cloud-init/${each.value.profile}.yaml.tftpl", {
    hostname       = each.key
    domain         = var.lab_network_domain
    username       = var.username
    user_password  = var.user_password
    ssh_public_key = var.ssh_public_key
  })

  # PL: JAWNA konfiguracja sieci gościa (cloud-init network v2): DHCP na KAŻDYM
  #     interfejsie ethernet (match "e*" => enp1s0/ens3/eth0...). Dobra praktyka
  #     dla obrazów cloud - nie polegamy na fallbacku cloud-init, żeby gość
  #     niezawodnie podniósł DHCP i dostał IP z sieci 'lab'/'default'.
  # EN: Explicit guest network config (cloud-init v2): DHCP on every ethernet NIC.
  #     Recommended for cloud images so the guest reliably brings up DHCP.
  network_config = <<-EOT
    version: 2
    ethernets:
      all-ethernets:
        match:
          name: "e*"
        dhcp4: true
  EOT
}
