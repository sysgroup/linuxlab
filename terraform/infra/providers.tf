# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  infra/providers.tf  -  połączenie do libvirt / libvirt connection
# ============================================================================
provider "libvirt" {
  uri = var.libvirt_uri
}
