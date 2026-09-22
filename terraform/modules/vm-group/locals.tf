# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  modules/vm-group/locals.tf  -  dane pochodne modułu / derived module data
# ============================================================================

locals {
  # PL: Mapa VM po filtrze only_groups (puste => wszystkie). To jedyne źródło,
  #     po którym iterują zasoby i pozostałe locale.
  # EN: VM map after the only_groups filter (empty => all). Single source the
  #     resources and the other locals iterate over.
  active_vms = length(var.only_groups) == 0 ? var.vms : {
    for k, v in var.vms : k => v if contains(var.only_groups, v.group)
  }

  # PL: Spłaszczona mapa dysków DODATKOWYCH: "klucz-dataN" -> {vm, rozmiar}.
  # EN: Flattened map of EXTRA data disks: "key-dataN" -> {vm, size}.
  extra_disks = { for item in flatten([
    for vk, vm in local.active_vms : [
      for idx, sz in vm.extra_disks_gib : {
        key      = "${vk}-data${idx + 1}"
        vm       = vk
        size_gib = sz
      }
    ]
  ]) : item.key => item }

  groups       = toset([for v in local.active_vms : v.group])
  vms_by_group = { for g in local.groups : g => sort([for k, v in local.active_vms : k if v.group == g]) }
}
