# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/variables.tf  -  wejścia modułu / module inputs
# ----------------------------------------------------------------------------
#  PL: To jest "API" modułu. Root podaje: mapę VM, pulę dysków roboczych, ID
#      golden images (czytane z roota base/ przez remote_state), nazwę sieci
#      lab oraz dane konta/klucz. Dzięki temu testboxes/ i infra/ współdzielą
#      JEDNĄ definicję zasobów (DRY), różniąc się tylko wejściami.
#  EN: This is the module's "API". The root passes the VM map, the working-disk
#      pool, the golden-image IDs (read from the base/ root via remote_state),
#      the lab network name and account/key data. So testboxes/ and infra/ share
#      ONE resource definition (DRY) and differ only by inputs.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 5): `variable` w MODULE = jego INPUT (publiczne „API").
#   Root podaje je w bloku `module "vms" { ... }`. Moduł NIE ma bloku `provider`
#   - dziedziczy go z roota (patrz versions.tf modułu). To standardowy wzorzec.
# ============================================================================

variable "vms" {
  description = "Mapa maszyn tej grupy/roota (kształt jak w starym var.vms)."
  type = map(object({
    group           = string
    profile         = string # base | desktop | docker | pbs | k3s
    distro          = string # klucz z katalogu distros (musi mieć golden image w base/)
    vcpus           = optional(number, 2)
    memory_mib      = optional(number, 2048)
    disk_gib        = optional(number, 10)
    network         = optional(string, "lab") # "default" | "lab"
    extra_disks_gib = optional(list(number), [])
    # PL: running=false => `terraform apply` ZATRZYMUJE domenę (graceful, in-place;
    #   definicja/dyski/IP zostają - to NIE jest destroy). Start z powrotem: running=true.
    #   Natywny dla Terraform odpowiednik `make down`/`make up` (te robią to przez virsh).
    #   Żeby zatrzymać całą grupę, ustaw running=false na wpisach w *.tfvars i zrób apply.
    # EN: running=false => apply gracefully STOPS the domain in-place (def/disks/IP kept,
    #   not a destroy); set true to start it again. Terraform-native equivalent of
    #   `make down`/`make up`. Stop a whole group by setting running=false in *.tfvars.
    running   = optional(bool, true)
    autostart = optional(bool, false) # czy domena startuje z hostem / start on host boot
  }))
}

# PL: Filtr "na części" w obrębie roota (np. tylko grupa testdeb spośród
#     testboxów). Puste = wszystkie VM przekazane do modułu.
# EN: In-root subset filter (e.g. only the testdeb group among the test boxes).
#     Empty = all VMs passed to the module.
variable "only_groups" {
  description = "Buduj tylko wybrane grupy (puste = wszystkie z `vms`)."
  type        = list(string)
  default     = []
}

variable "vm_pool" {
  description = "Pula na dyski robocze VM i ISO cloud-init (np. istniejąca 'images')."
  type        = string
}

# PL: Mapa dystrybucja -> ID golden image. Pochodzi z outputu roota base/
#     (terraform_remote_state). vm_disk robi z niej warstwę CoW.
# EN: Map distro -> golden-image volume ID, sourced from the base/ root's output
#     (terraform_remote_state). vm_disk uses it as a CoW backing layer.
variable "base_volume_ids" {
  description = "Mapa distro -> ID woluminu golden image (z roota base/)."
  type        = map(string)
}

# PL: Jak zbudować dysk systemowy VM z golden image:
#   "cow"  - cienka warstwa copy-on-write na golden image (base_volume_id).
#            Oszczędna: dysk VM zajmuje tylko RÓŻNICĘ względem współdzielonego
#            golden image. Domyślna i zgodna z ideą "golden image".
#   "copy" - pełna, SAMODZIELNA kopia obrazu (bez backing-chain). Każdy VM = pełny
#            obraz (więcej miejsca), za to niezależny od golden image (można go
#            potem usunąć). Dla puli "dir" base_volume_ids[distro] to ścieżka pliku.
#   ⚠️ AppArmor (Ubuntu): `virt-aa-helper` NIE whitelistuje pliku BACKING
#      warstwy CoW - sprawdzone: profil .files dostaje tylko overlay + cloud-init,
#      a NIE golden (nawet gdy golden leży w tej samej puli `images`!). Skutek:
#      qemu nie może czytać backing => SeaBIOS "could not read the boot disk".
#      Na takich hostach UŻYWAJ disk_strategy="copy" (brak backing => nie ma czego
#      whitelistować, dysk jest samodzielny), albo dodaj ścieżkę golden do AppArmor
#      na hoście (np. security_driver="none" w /etc/libvirt/qemu.conf - wymaga roota).
# EN: "cow" = thin CoW overlay (default, space-efficient) BUT on Ubuntu/AppArmor
#   virt-aa-helper does NOT whitelist the CoW backing file (verified: .files lists
#   only the overlay + cloud-init, not the golden - even in the same pool), so qemu
#   can't read the backing => SeaBIOS "could not read the boot disk". On such hosts
#   use "copy" (standalone, no backing), or whitelist the golden in host AppArmor.
# 🎓 EGZAMIN: base_volume_id i source wykluczają się; size i source też (ten provider).
#   Wybór robimy conditionalem (ternary); nieużyta gałąź = null => atrybut pominięty.
variable "disk_strategy" {
  description = "Dysk VM z golden image: 'cow' (overlay) albo 'copy' (pełna kopia)."
  type        = string
  default     = "cow"

  validation {
    condition     = contains(["cow", "copy"], var.disk_strategy)
    error_message = "disk_strategy musi być 'cow' albo 'copy'."
  }
}

# PL: Czy `apply` ma CZEKAĆ, aż VM dostanie adres IP z DHCP (wait_for_lease).
#     true  = wygodnie (output od razu pokazuje IP), ale apply PADA, jeśli gość
#             nie zdąży/nie zdoła wziąć leasu w czasie providera (~5 min) - np.
#             wolny boot, brak DHCP w obrazie, problem sieci gościa.
#     false = apply kończy się po utworzeniu domeny; IP pobierzesz później
#             (`virsh domifaddr`, agent). Bezpieczniejsze do CI / kapryśnych hostów.
# EN: Whether `apply` should BLOCK until the VM gets a DHCP lease. true = IP shown
#     right after apply but apply FAILS if no lease in time; false = apply returns
#     once the domain is defined, fetch the IP later (virsh/agent).
variable "wait_for_lease" {
  description = "Czy apply ma czekać na adres IP z DHCP (true) czy nie (false)."
  type        = bool
  default     = true
}

# PL: Typ maszyny (chipset). "q35" (nowoczesny, domyślny) albo "pc" (i440fx).
#     UWAGA: prawdziwą przyczyną nieudanego bootu NIE był machine type, tylko
#     FORMAT dysku (qcow2 deklarowany jako raw - patrz vm_disk w storage.tf). Po fixie
#     formatu bootują OBA: q35 i pc. q35 nie ma IDE, więc cloud-init i tak podpinamy
#     jako dysk virtio (machine-agnostycznie) - patrz vms.tf.
# EN: Machine type. "q35" (modern, default) or "pc" (i440fx). NOTE: the real boot
#     blocker was the disk FORMAT (qcow2 declared as raw), not the machine - both
#     work once the format matches. cloud-init is attached as a virtio disk anyway.
variable "machine" {
  description = "Typ maszyny libvirt: 'q35' (domyślnie) albo 'pc' (i440fx)."
  type        = string
  default     = "q35"
}

# PL: Firmware. DOMYŚLNIE "uefi" (OVMF) - z dyskiem RAW (patrz vm_disk) OVMF czyta
#     GPT/ESP oryginalnego cloud image i bootuje BOOTX64.EFI, BEZ grub-pc i BEZ roota.
#     "bios" (SeaBIOS) wymaga obrazu z kodem boot BIOS (skrypt make-golden-bios-bootable.sh).
# EN: Firmware. Default "uefi" (OVMF): with a RAW disk, OVMF reads the cloud image's
#     GPT/ESP and boots BOOTX64.EFI - no grub-pc, no root. "bios" needs a BIOS-bootable image.
variable "firmware" {
  description = "Firmware: 'uefi' (OVMF, domyślnie) albo 'bios' (SeaBIOS)."
  type        = string
  default     = "uefi"
}

variable "ovmf_code" {
  description = "Ścieżka OVMF_CODE (firmware=uefi)."
  type        = string
  default     = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "ovmf_vars" {
  description = "Ścieżka szablonu OVMF_VARS (firmware=uefi)."
  type        = string
  default     = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

variable "lab_network_name" {
  description = "Nazwa sieci lab (z roota base/). Sieć 'default' nie jest zarządzana."
  type        = string
}

variable "lab_network_domain" {
  description = "Domena DNS gości wstrzykiwana do cloud-init (np. 'lab')."
  type        = string
  default     = "lab"
}

variable "username" {
  description = "Login konta administracyjnego zakładanego w VM."
  type        = string
}

variable "user_password" {
  description = "Hasło konta (konsola/GUI)."
  type        = string
  sensitive   = true
}

# PL: TREŚĆ klucza publicznego (root czyta plik i przekazuje zawartość).
# EN: The public key CONTENTS (the root reads the file and passes the string).
variable "ssh_public_key" {
  description = "Zawartość publicznego klucza SSH wstrzykiwanego do VM."
  type        = string
}

variable "libvirt_uri" {
  description = "URI libvirt - używane tylko w podpowiedziach outputów (ssh)."
  type        = string
  default     = "qemu:///system"
}
