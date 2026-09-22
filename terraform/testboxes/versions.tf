# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  testboxes/versions.tf  -  wymagane wersje / required versions
# ----------------------------------------------------------------------------
#  PL: Root maszyn testowych (testdeb + testubu). Pin providera 0.8.3 jak w base/.
#  EN: The test-box root (testdeb + testubu). Pin libvirt 0.8.3 like in base/.
# ============================================================================
terraform {
  required_version = ">= 1.3"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}
