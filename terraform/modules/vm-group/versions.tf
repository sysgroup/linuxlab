# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/versions.tf  -  wymagania modułu / module requirements
# ----------------------------------------------------------------------------
#  PL: Moduł NIE konfiguruje providera (nie ma bloku `provider`) - dziedziczy go
#      z roota, który go wywołuje. Deklaruje tylko, JAKIEGO providera używa.
#      Wersję pinuje root (base/, testboxes/, infra/), nie moduł.
#  EN: A module does NOT configure the provider (no `provider` block) - it
#      inherits it from the calling root. It only declares WHICH provider it
#      uses. The version is pinned by the roots, not the module.
# ============================================================================
terraform {
  required_version = ">= 1.3"
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}
