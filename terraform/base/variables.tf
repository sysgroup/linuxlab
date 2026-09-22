# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/variables.tf  -  wejścia warstwy bazowej / base layer inputs
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 8 - variables):
#   - INPUT VARIABLE ma: type, default, description (i opcjonalnie sensitive,
#     validation). Odwołanie: var.nazwa.
#   - TYPY: string, number, bool, list(...), set(...), map(...), object({...}),
#     tuple([...]), any. Tu masz map(object({...})) (`distros`) i list(string)
#     (`enabled_distros`).
#   - PRECEDENCJA nadpisań (rosnąco): default -> terraform.tfvars / *.auto.tfvars
#     -> zmienna środowiskowa TF_VAR_nazwa -> flaga -var / -var-file (najsilniejsza).
# ============================================================================

variable "libvirt_uri" {
  description = "URI połączenia do libvirt."
  type        = string
  default     = "qemu:///system"
}

# --- Pula golden / golden pool ----------------------------------------------
variable "golden_pool_name" {
  description = "Nazwa puli na obrazy bazowe (golden images)."
  type        = string
  default     = "golden"
}

variable "golden_pool_path" {
  description = "Katalog dla puli 'golden' na hoście."
  type        = string
  default     = "/var/lib/libvirt/images/golden"
}

# PL: Minimalny rozmiar KAŻDEGO golden image (GiB). Golden są RAW + `source`, więc
#     provider (0.8.3) nie pozwala podać `size` obok `source`. Rozmiar wymuszamy
#     PO utworzeniu, grow-only, przez terraform_data.golden_resize (patrz images.tf).
#     Kopie testboxów (copy mode) dziedziczą ten rozmiar; cloud-init growpart
#     rozszerza root gościa. 0 = wyłącz wymuszanie.
# EN: Minimum size (GiB) of EVERY golden image. Goldens are RAW + `source`, so the
#     provider can't take `size` next to `source`; we enforce it after creation,
#     grow-only, via terraform_data.golden_resize (see images.tf). The testboxes
#     copies inherit it; cloud-init growpart grows the guest root. 0 = disable.
variable "golden_min_size_gib" {
  description = "Minimalny rozmiar każdego golden image w GiB (grow-only, wymuszany po utworzeniu). 0 = wyłącz."
  type        = number
  default     = 10
}

# --- Sieć laboratoryjna / lab network ---------------------------------------
variable "lab_network_name" {
  description = "Nazwa tworzonej sieci NAT 'lab' (dla maszyn testowych)."
  type        = string
  default     = "lab"
}

variable "lab_network_cidr" {
  description = "Adresacja sieci laboratoryjnej (CIDR)."
  type        = string
  default     = "192.168.123.0/24"
}

variable "lab_network_domain" {
  description = "Domena DNS gości (np. deb13.lab)."
  type        = string
  default     = "lab"
}

# ============================================================================
#  CLOUD IMAGES - czym są i jak ich używamy / what they are and how we use them
# ----------------------------------------------------------------------------
#  PL: "Cloud image" to GOTOWY, minimalny obraz dysku (qcow2 / .img) z już
#      zainstalowanym systemem i pakietem `cloud-init`. W odróżnieniu od ISO
#      instalacyjnego NIE przechodzisz instalatora - obraz bootuje od razu,
#      a `cloud-init` przy pierwszym starcie konfiguruje hosta z danych, które
#      wstrzykujemy (user, klucz SSH, pakiety - patrz modules/vm-group/cloud-init).
#      Dysk jest mały (kilkaset MB) i sam rośnie do żądanego rozmiaru przez
#      `growpart` przy starcie. To dlatego nasze VM stawiają się w sekundy.
#
#      Wariant "genericcloud" (Debian) / "server-cloudimg" (Ubuntu) jest
#      zoptymalizowany pod hypervisory (virtio/KVM) - idealny dla libvirt.
#
#      JAK SĄ AKTUALIZOWANE: dystrybucje publikują OKRESOWE przebudowy obrazu
#      (z wbudowanymi poprawkami bezpieczeństwa) w katalogach DATOWANYCH:
#        - Debian: serial "YYYYMMDD-BUILD" (np. 20260601-2496) - w nazwie
#          KATALOGU ORAZ w nazwie pliku. `latest/` wskazuje najnowszy.
#          ⚠️ Mirror Debiana USUWA stare snapshoty po kilku tygodniach.
#        - Ubuntu: katalog "release-YYYYMMDD" (np. release-20260518) - data tylko
#          w nazwie katalogu, nazwa pliku stała. `release/` = najnowszy.
#      Dlatego Debian i Ubuntu mają RÓŻNY układ URL - stąd trzymamy PEŁNE URL-e,
#      a nie składamy ich z samej daty.
#
#  🎓 EGZAMIN - to świetny przykład trade-offu POWTARZALNOŚCI (reproducibility):
#      - "latest"  = wygoda + zawsze świeże poprawki, ale NIEDETERMINISTYCZNE:
#        ten sam `apply` w różne dni pobierze RÓŻNY obraz. Brak powtarzalności.
#      - "pinned"  = konkretny snapshot z danego dnia => POWTARZALNY build (jak
#        pinowanie wersji providera w versions.tf!), ale obraz się starzeje i
#        trzeba go świadomie podbijać.
#
#  EN: A cloud image is a ready, minimal disk image with the OS + cloud-init
#      pre-installed; it boots straight away (no installer) and cloud-init
#      configures it on first boot. "latest" = convenient but non-deterministic;
#      "pinned" (a dated snapshot) = reproducible build, but ages. Debian pins by
#      serial "YYYYMMDD-BUILD" (in dir AND filename); Ubuntu by "release-YYYYMMDD"
#      (dir only). Debian prunes old snapshots after a few weeks.
# ----------------------------------------------------------------------------
# PL: Katalog dystrybucji. Każdy wpis ma DWA kanały: latest_url (zawsze aktualny)
#     i opcjonalny pinned_url (konkretny dzień). Który wybrać -> var.image_channel.
# EN: Distro catalog. Each entry has TWO channels: latest_url and optional
#     pinned_url. Which one is used is decided by var.image_channel.
variable "distros" {
  description = "Mapowanie dystrybucja -> cloud-image (kanał latest + opcjonalny pinned)."
  type = map(object({
    pretty     = string
    latest_url = string           # zawsze aktualny / always-newest
    pinned_url = optional(string) # konkretny snapshot / a dated snapshot (null = brak)
  }))

  # PL: pinned_url poniżej to PRZYKŁADY z istniejących snapshotów (Debian:
  #     20260601-2496; Ubuntu: release-2026MMDD). ⚠️ Mogą zostać usunięte z
  #     mirrora - jeśli `apply` z image_channel=pinned da 404, weź aktualny
  #     serial/datę z listingu:
  #       https://cloud.debian.org/images/cloud/<codename>/
  #       https://cloud-images.ubuntu.com/releases/<wersja>/
  default = {
    "debian-11" = {
      pretty     = "Debian 11 (bullseye)"
      latest_url = "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
      pinned_url = "https://cloud.debian.org/images/cloud/bullseye/20260601-2496/debian-11-genericcloud-amd64-20260601-2496.qcow2"
    }
    "debian-12" = {
      pretty     = "Debian 12 (bookworm)"
      latest_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
      pinned_url = "https://cloud.debian.org/images/cloud/bookworm/20260601-2496/debian-12-genericcloud-amd64-20260601-2496.qcow2"
    }
    "debian-13" = {
      pretty     = "Debian 13 (trixie)"
      latest_url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
      pinned_url = "https://cloud.debian.org/images/cloud/trixie/20260601-2496/debian-13-genericcloud-amd64-20260601-2496.qcow2"
    }
    "ubuntu-2204" = {
      pretty     = "Ubuntu 22.04 LTS (jammy)"
      latest_url = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
      pinned_url = "https://cloud-images.ubuntu.com/releases/22.04/release-20260515/ubuntu-22.04-server-cloudimg-amd64.img"
    }
    "ubuntu-2404" = {
      pretty     = "Ubuntu 24.04 LTS (noble)"
      latest_url = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
      pinned_url = "https://cloud-images.ubuntu.com/releases/24.04/release-20260518/ubuntu-24.04-server-cloudimg-amd64.img"
    }
    # PL: 26.04 „resolute" wyszło - zastąpiło placeholder 25.10 („questing").
    #     Katalog /releases/26.04/ przekierowuje na /releases/resolute/, więc
    #     trzymamy wersję numeryczną (spójnie z 22.04/24.04).
    # EN: 26.04 "resolute" shipped and replaced the 25.10 stand-in. The
    #     /releases/26.04/ dir redirects to /releases/resolute/, so we keep the
    #     numeric form (consistent with 22.04/24.04).
    "ubuntu-2604" = {
      pretty     = "Ubuntu 26.04 LTS (resolute)"
      latest_url = "https://cloud-images.ubuntu.com/releases/26.04/release/ubuntu-26.04-server-cloudimg-amd64.img"
      pinned_url = "https://cloud-images.ubuntu.com/releases/26.04/release-20260731/ubuntu-26.04-server-cloudimg-amd64.img"
    }
  }
}

# --- Kanał obrazu: latest vs pinned / image channel -------------------------
# PL: "latest" => latest_url (świeże, niedeterministyczne). "pinned" => pinned_url
#     (powtarzalne). Gdy "pinned", a distro nie ma pinned_url - spada na latest_url.
# EN: "latest" => latest_url; "pinned" => pinned_url (falls back to latest_url if a
#     distro has no pinned_url). See base/images.tf -> local.distro_url.
# 🎓 EGZAMIN: `validation` w zmiennej - sprawdza wartość PRZY plan/apply i przerywa
#    z czytelnym błędem. Częsty konstrukt na egzaminie (Objective 8).
variable "image_channel" {
  description = "Który kanał obrazu: 'latest' albo 'pinned'."
  type        = string
  default     = "latest"

  validation {
    condition     = contains(["latest", "pinned"], var.image_channel)
    error_message = "image_channel musi być 'latest' albo 'pinned'."
  }
}

# --- Twarde nadpisania URL per distro / per-distro URL overrides -------------
# PL: Najwygodniejszy sposób na "zbuduj z KONKRETNEGO DNIA": podajesz pełny URL
#     dla wybranych distro, np. w base/pinned.tfvars. Ma PIERWSZEŃSTWO przed
#     image_channel (patrz precedencja w base/images.tf). Klucz = distro, wartość = URL.
#     Przykład gotowy: base/pinned.tfvars.example
# EN: Per-distro full-URL override (highest precedence) - the easy knob for
#     "build from a specific day". See base/pinned.tfvars.example.
variable "image_overrides" {
  description = "Nadpisz URL obrazu dla wybranych distro (np. przypnij do konkretnego dnia)."
  type        = map(string)
  default     = {}
}

# --- Które obrazy faktycznie zbudować / which images to actually build ------
# PL: WAŻNE przy splicie: base/ nie zna mapy VM, więc sam decydujesz, KTÓRE
#     golden images pobrać. Puste = wszystkie z katalogu `distros`. Chcesz tylko
#     debianowe testboxy bez pobierania Ubuntu? Ustaw:
#       enabled_distros = ["debian-11","debian-12","debian-13"]
#     Pamiętaj: musi pokrywać UNIĘ dystrybucji wszystkich wdrażanych rootów
#     (testboxes/ + infra/), inaczej ich vm_disk nie znajdzie golden image.
# EN: IMPORTANT after the split: base/ doesn't know the VM map, so YOU choose
#     which golden images to download. Empty = all of `distros`. It must cover
#     the UNION of distros used by every deployed root (testboxes/ + infra/).
variable "enabled_distros" {
  description = "Lista distro do zbudowania (puste = wszystkie z `distros`)."
  type        = list(string)
  default     = []
}
