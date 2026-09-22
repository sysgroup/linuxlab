# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/vms.tf  -  domeny VM / VM domains
# ----------------------------------------------------------------------------
#  PL: Definicja domeny libvirt powielana dla każdej pozycji local.active_vms.
#      Dyski, cloud-init i lokale są rozdzielone do osobnych plików modułu.
#  EN: A libvirt domain definition instantiated for every local.active_vms item.
#      Storage, cloud-init and locals live in separate module files.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN - w tym zasobie znajdziesz:
#   - META-ARGUMENT `for_each` (vs `count`) + each.key / each.value,
#   - `dynamic` bloki (zagnieżdżone bloki generowane w pętli),
#   - conditional (profile == "desktop" ? [1] : []),
#   - funkcje `split` i `element`,
#   - IMPLICIT DEPENDENCIES (domena odwołuje się do dysku i cloud-init → kolejność).
# ============================================================================

# DOMENA = wirtualna maszyna / DOMAIN = the VM
resource "libvirt_domain" "vm" {
  for_each = local.active_vms

  name      = each.key
  memory    = each.value.memory_mib
  vcpu      = each.value.vcpus
  running   = each.value.running
  autostart = each.value.autostart

  qemu_agent = true
  # PL: Chipset (q35/pc). Boot zależy od FORMATU dysku (patrz vm_disk), nie od machine.
  # EN: Chipset (q35/pc). Boot depends on the disk FORMAT (see vm_disk), not the machine.
  machine = var.machine

  # PL: UEFI (OVMF) - z dyskiem RAW bootuje oryginalne cloud images (GPT/ESP), bez grub-pc.
  # EN: UEFI (OVMF) - with a RAW disk boots stock cloud images (GPT/ESP), no grub-pc.
  firmware = var.firmware == "uefi" ? var.ovmf_code : null
  dynamic "nvram" {
    for_each = var.firmware == "uefi" ? [1] : []
    content {
      file     = "/var/lib/libvirt/qemu/nvram/${each.key}_VARS.fd"
      template = var.ovmf_vars
    }
  }

  cpu {
    mode = "host-passthrough"
  }

  # PL: Dysk systemowy podajemy jako `file` (ŚCIEŻKA), nie `volume_id`. To DAJE w
  #     XML `<disk type='file'>`, a nie `<disk type='volume'>`. KLUCZOWE na Ubuntu:
  #     `virt-aa-helper` (generator profilu AppArmor) NIE rozwiązuje dysków
  #     type='volume' (nie zagląda do pul) => nie wpisuje ścieżki do profilu =>
  #     qemu dostaje "Could not open ...: Permission denied". Z type='file' helper
  #     whitelistuje dysk (i jego backing chain). Dla puli "dir" .id woluminu == ścieżka.
  # EN: Use `file` (a PATH) not `volume_id` => XML `<disk type='file'>`. On Ubuntu,
  #     virt-aa-helper can't resolve type='volume' disks, so AppArmor blocks them;
  #     type='file' is whitelisted (incl. its backing chain). For "dir" pools the
  #     volume .id is its file path.
  disk {
    file = var.disk_strategy == "copy" ? terraform_data.vm_disk_resize[each.key].output.volume_id : libvirt_volume.vm_disk[each.key].id
  }

  # PL: Seed cloud-init (NoCloud) jako DYSK virtio (vdb), NIE jako cdrom IDE -
  #     `cloudinit=` providera wymusza IDE, a q35 nie ma IDE. cloud-init znajduje
  #     seed po ETYKIECIE woluminu 'cidata'. .id to "ścieżka;uuid" => split.
  # EN: cloud-init NoCloud seed as a virtio DISK (q35 has no IDE; `cloudinit=` forces
  #     IDE). cloud-init finds it by the 'cidata' label. .id is "path;uuid" => split.
  disk {
    file = element(split(";", libvirt_cloudinit_disk.vm_init[each.key].id), 0)
  }

  # Dyski dodatkowe tej VM (też przez `file`, ten sam powód co wyżej).
  # 🎓 EGZAMIN: `dynamic` generuje ZAGNIEŻDŻONE BLOKI (tu: kolejne `disk {}`) w pętli.
  #   `dynamic` jest do bloków; do całych zasobów służy for_each/count na zasobie.
  #   Iterator domyślnie nazywa się jak blok (disk) => disk.key / disk.value.
  dynamic "disk" {
    for_each = { for k, d in local.extra_disks : k => d if d.vm == each.key }
    content {
      file = libvirt_volume.extra_disk[disk.key].id
    }
  }

  # PL: Poprawki XML, których provider nie wyraża: format *.qcow2 (dyski danych),
  #     zegary bez emulowanego HPET i brak domyślnego SPICE/cirrus dla VM bez
  #     pulpitu. Oba ostatnie to realny koszt CPU/energii hosta (linuxlab.pl, artykuł o energii).
  #     Zmiana `xslt` odtwarza domenę (dyski zostają) - czytaj plan.
  # EN: XML fixes the provider can't express: qcow2 driver type, no emulated HPET,
  #     no implicit SPICE/cirrus on headless VMs. Changing `xslt` replaces the domain.
  xml {
    xslt = templatefile("${path.module}/domain.xsl.tftpl", {
      headless = each.value.profile != "desktop"
    })
  }

  network_interface {
    network_name = local.net_name[each.value.network]
    # PL: Czekamy na lease tylko gdy VM startuje I gdy wait_for_lease=true.
    # EN: Wait for a lease only if the VM runs AND wait_for_lease is enabled.
    wait_for_lease = var.wait_for_lease && each.value.running
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  # SPICE + QXL tylko dla profilu "desktop" / only for the "desktop" profile.
  # PL: Brak bloku NIE wystarcza - provider dodaje wtedy własny SPICE; pozostałe
  #     VM czyści z grafiki domain.xsl.tftpl (headless = true).
  # EN: Omitting the block is not enough (the provider adds SPICE anyway);
  #     domain.xsl.tftpl strips it from headless VMs.
  dynamic "graphics" {
    for_each = each.value.profile == "desktop" ? [1] : []
    content {
      type        = "spice"
      listen_type = "address"
      autoport    = true
    }
  }
  dynamic "video" {
    for_each = each.value.profile == "desktop" ? [1] : []
    content {
      type = "qxl"
    }
  }
}
