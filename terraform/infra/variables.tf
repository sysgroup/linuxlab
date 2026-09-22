# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  infra/variables.tf  -  wejścia roota "infra" / "infra" root inputs
# ----------------------------------------------------------------------------
#  PL: Mapa `vms` to maszyny usługowe: stacja robocza, PBS, AWX, Docker, monitoring.
#      Wszystkie w sieci "default". `awx` i `mon` domyślnie WYŁĄCZONE (running=false).
#  EN: The `vms` map holds the service machines (workstation, PBS, AWX, Docker,
#      monitoring). All on the "default" network. `awx`/`mon` are off by default.
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

variable "user_password" {
  description = "Hasło konta (zmień po pierwszym logowaniu!)."
  type        = string
  default     = "changeme"
  sensitive   = true
}

variable "lab_network_domain" {
  description = "Domena DNS gości."
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

# PL: 'uefi' (domyślnie) albo 'bios'.
# EN: 'uefi' (default) or 'bios'.
variable "firmware" {
  description = "Firmware: 'uefi' (domyślnie) albo 'bios'."
  type        = string
  default     = "uefi"
}

# PL: Filtr "na części": np. tylko backup (pbs). Puste = wszystkie infra.
#     Przykład: terraform plan -var='only_groups=["backup"]'
# EN: In-root subset filter, e.g. only backup (pbs). Empty = all infra.
variable "only_groups" {
  description = "Buduj tylko wybrane grupy (puste = wszystkie infra)."
  type        = list(string)
  default     = []
}

# ============================================================================
#  vms  -  maszyny usługowe / service machines
# ============================================================================
variable "vms" {
  description = "Definicja maszyn infra."
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
    # ---- Stacja robocza (Kubuntu + VS Code + Ansible + Chrome)
    "kdev" = {
      group      = "dev"
      profile    = "desktop"
      distro     = "ubuntu-2404"
      vcpus      = 4
      memory_mib = 8192
      disk_gib   = 20
      network    = "default"
    }

    # ---- Proxmox Backup Server (Debian 12), 4 dyski danych po 50 GiB
    "pbs" = {
      group           = "backup"
      profile         = "pbs"
      distro          = "debian-12"
      vcpus           = 2
      memory_mib      = 4096
      disk_gib        = 10
      network         = "default"
      extra_disks_gib = [50, 50, 50, 50]
    }

    # ---- AWX na Kubernetes (k3s).
    "awx" = {
      group      = "awx"
      profile    = "k3s"
      distro     = "ubuntu-2404"
      vcpus      = 4
      memory_mib = 8192
      disk_gib   = 40
      network    = "default"
      running    = true
      autostart  = true
    }

    # ---- Docker host: Uptime Kuma + MariaDB (compose)
    "docker" = {
      group      = "services"
      profile    = "docker"
      distro     = "debian-13"
      vcpus      = 2
      memory_mib = 4096
      disk_gib   = 20
      network    = "default"
    }

    # ---- Monitoring: Prometheus + Grafana + Loki. Domyślnie WYŁĄCZONA.
    "mon" = {
      group      = "monitoring"
      profile    = "docker"
      distro     = "debian-13"
      vcpus      = 4
      memory_mib = 6144
      disk_gib   = 30
      network    = "default"
      running    = false
    }
  }
}
