# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/network.tf  -  wybór sieci VM / VM network selection
# ----------------------------------------------------------------------------
#  PL: Sama sieć "lab" jest zarządzana w base/network.tf. Tutaj mapujemy nazwę
#      logiczną z definicji VM na sieć libvirt podpinaną w vms.tf.
#  EN: The "lab" network itself is managed in base/network.tf. Here the logical
#      VM network name is mapped to the libvirt network attached in vms.tf.
# ============================================================================

locals {
  net_name = {
    default = "default"
    lab     = var.lab_network_name
  }
}
