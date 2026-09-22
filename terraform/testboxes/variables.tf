# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  testboxes/variables.tf  -  wejścia roota maszyn testowych / test-box inputs
# ----------------------------------------------------------------------------
#  PL: Mapa `vms` to TYLKO maszyny testowe (grupy testdeb + testubu). Reszta
#      laboratorium (infra) żyje w osobnym roocie infra/ z osobnym stanem.
#  EN: The `vms` map holds ONLY the test boxes (testdeb + testubu groups). The
#      rest of the lab (infra) lives in the separate infra/ root with its own state.
# ============================================================================

variable "libvirt_uri" {
  description = "URI połączenia do libvirt."
  type        = string
  default     = "qemu:///system"
}

variable "vm_pool" {
  description = "Istniejąca pula na dyski robocze VM i ISO cloud-init."
  type        = string
  default     = "images"
}

# PL: Ścieżka do stanu warstwy base/ (golden images + sieć lab). Domyślnie
#     sąsiedni katalog - terraform uruchamiany jest w testboxes/.
# EN: Path to the base/ layer state (golden images + lab network). Defaults to
#     the sibling dir - terraform runs inside testboxes/.
variable "base_state_path" {
  description = "Ścieżka do terraform.tfstate roota base/."
  type        = string
  default     = "../base/terraform.tfstate"
}

variable "ssh_public_key_path" {
  description = "Ścieżka do publicznego klucza SSH wstrzykiwanego do VM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "username" {
  description = "Login konta administracyjnego tworzonego w każdej VM."
  type        = string
  default     = "admin"
}

# 🎓 EGZAMIN (Objective 7): `sensitive = true` ukrywa wartość w outpucie planu jako
#   "(sensitive value)" - ALE w pliku stanu (terraform.tfstate) hasło i tak leży
#   JAWNIE. Dlatego *.tfstate jest w .gitignore i chronisz backend.
variable "user_password" {
  description = "Hasło konta (zmień po pierwszym logowaniu!)."
  type        = string
  default     = "changeme"
  sensitive   = true
}

variable "lab_network_domain" {
  description = "Domena DNS gości (np. deb13.lab)."
  type        = string
  default     = "lab"
}

# PL: 'cow' = cienki overlay współdzielący golden image (domyślnie, oszczędny);
#     'copy' = pełna, niezależna kopia (więcej miejsca) - patrz module/vm-group.
# EN: 'cow' (default) thin shared overlay; 'copy' full standalone copy (more disk).
variable "disk_strategy" {
  description = "Dysk VM: 'cow' (overlay) albo 'copy' (pełna kopia)."
  type        = string
  default     = "cow"
}

# PL: true = apply czeka na IP z DHCP; false = nie czeka (IP pobierzesz później).
#     Ustaw false, jeśli boot/DHCP gościa bywa wolny i apply pada na czekaniu.
# EN: true = apply waits for a DHCP lease; false = don't wait (fetch IP later).
variable "wait_for_lease" {
  description = "Czy apply ma czekać na adres IP z DHCP."
  type        = bool
  default     = true
}

# PL: Domyślnie 'q35'. Boot zależy od formatu dysku i firmware, nie od samego chipsetu.
# EN: Default 'q35'. Boot depends on disk format and firmware, not the chipset alone.
variable "machine" {
  description = "Typ maszyny: 'q35' (domyślnie) albo 'pc' (i440fx)."
  type        = string
  default     = "q35"
}

# PL: 'uefi' (domyślnie, OVMF + dysk raw = boot bez grub-pc/roota) albo 'bios'.
# EN: 'uefi' (default) or 'bios'.
variable "firmware" {
  description = "Firmware: 'uefi' (domyślnie) albo 'bios'."
  type        = string
  default     = "uefi"
}

# PL: Filtr "na części" w obrębie tego roota: np. tylko Debiany testowe.
#     Przykład: terraform plan -var='only_groups=["testdeb"]'
# EN: In-root subset filter, e.g. only the Debian test boxes.
variable "only_groups" {
  description = "Buduj tylko wybrane grupy (puste = testdeb + testubu)."
  type        = list(string)
  default     = []
}

# ============================================================================
#  vms  -  maszyny testowe / test boxes
# ----------------------------------------------------------------------------
#  PL: Pola opcjonalne mają wartości domyślne (patrz module/vm-group). Domyślnie
#      wszystkie w sieci "lab" i running=true.
#  EN: Optional fields have defaults (see module/vm-group). All on the "lab"
#      network, running=true by default.
# ============================================================================
# 🎓 EGZAMIN (Objective 8 - types): map(object({...})) z optional(type, default).
#   optional() (TF >= 1.3) pozwala POMINĄĆ pole w wartości - dostaje default.
#   Dlatego wiersze testdeb to tylko {group, profile, distro}. Nadpiszesz mapę np.
#   przez -var / terraform.tfvars (patrz precedencja w base/variables.tf).
variable "vms" {
  description = "Definicja maszyn testowych."
  type = map(object({
    group           = string
    profile         = string
    distro          = string
    vcpus           = optional(number, 2)
    memory_mib      = optional(number, 2048)
    disk_gib        = optional(number, 10)
    network         = optional(string, "lab")
    extra_disks_gib = optional(list(number), [])
    running         = optional(bool, true)
    autostart       = optional(bool, false)
  }))

  default = {
    # ---- Maszyny testowe Debian (grupa "testdeb") - cel playbooków Ansible
    "deb11" = { group = "testdeb", profile = "base", distro = "debian-11" }
    "deb12" = { group = "testdeb", profile = "base", distro = "debian-12" }
    "deb13" = { group = "testdeb", profile = "base", distro = "debian-13" }

    # ---- Maszyny testowe Ubuntu (grupa "testubu")
    "ubu2204" = { group = "testubu", profile = "base", distro = "ubuntu-2204" }
    "ubu2404" = { group = "testubu", profile = "base", distro = "ubuntu-2404" }
    "ubu2604" = { group = "testubu", profile = "base", distro = "ubuntu-2604" }
  }
}
