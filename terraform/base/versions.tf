# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  base/versions.tf  -  wymagane wersje / required versions
# ----------------------------------------------------------------------------
#  PL: Root "base" = WSPÓLNA WARSTWA: pula golden, golden images i sieć lab.
#      Pin providera 0.8.3 (lekcja z głównego README - "~> 0.8" wpuściło 0.9.x
#      i zepsuło validate). Każdy root pinuje providera u siebie.
#  EN: The "base" root = SHARED LAYER: golden pool, golden images, lab network.
#      We pin libvirt 0.8.3 (see the main README lesson). Each root pins it.
# ----------------------------------------------------------------------------
#  🎓 EGZAMIN (Objective 3 - Terraform basics / providers):
#   - `required_version` = wersja narzędzia Terraform CLI; `required_providers`
#     = wersje PROVIDERÓW. To dwie różne rzeczy.
#   - `source = "dmacvicar/libvirt"` to adres w Terraform Registry: <NAMESPACE>/<TYPE>.
#   - Version constraints: `= 0.8.3` (pin), `>= 0.8`, `~> 0.8.0` (>=0.8.0,<0.9.0),
#     `~> 0.8` (>=0.8.0,<1.0.0).
#   - `terraform init` czyta TEN blok, pobiera plugin do .terraform/ i pinuje
#     wersje+hashe w .terraform.lock.hcl (lock file COMMITUJESZ; .terraform/ NIE).
#     `terraform init -upgrade` podbija wersje w ramach constraintów.
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
