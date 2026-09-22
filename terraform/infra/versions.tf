# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  infra/versions.tf  -  wymagane wersje / required versions
# ----------------------------------------------------------------------------
#  PL: Root maszyn "infra" (kdev, pbs, awx, docker, mon). Pin providera 0.8.3.
#  EN: The "infra" root (kdev, pbs, awx, docker, mon). Pin libvirt 0.8.3.
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
