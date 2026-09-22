# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/providers.tf  -  połączenie do libvirt / libvirt connection
# ----------------------------------------------------------------------------
#  PL: qemu:///system - systemowy libvirtd (jak virt-manager). Należysz do grupy
#      "libvirt", więc bez sudo.
#  EN: qemu:///system - the host-wide libvirtd. You are in the "libvirt" group.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 3): versions.tf mówił KTÓRY provider (i w jakiej wersji);
#   blok `provider` to KONFIGURACJA - JAK się połączyć. Jeden provider może mieć
#   wiele konfiguracji przez `alias` (np. dwa regiony) - tu mamy jedną, domyślną.
# ============================================================================
provider "libvirt" {
  uri = var.libvirt_uri
}
