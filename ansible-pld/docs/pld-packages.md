# PLD Linux Th - base packages

The `pld_base` role describes a small baseline for a fresh PLD Th host. It
installs only missing packages through the local `pld_poldek` module; it does
not remove existing RPMs.

## Profiles

| Profile | When | Contents |
|---|---|---|
| `core` | always | time synchronization, logging, administrative, and diagnostic tools |
| `kvm_guest` | KVM guest | `qemu-guest-agent` |
| `kvm_irqbalance` | KVM and `pld_base_enable_irqbalance: true` | `irqbalance` |
| `bare_metal` | physical host | `dmidecode`, `lm_sensors`, `smartmontools` |
| `monitoring` | `pld-setup-monitoring.yml` | NRPE and required plugins |
| `admin_toolbox` | `pld_base_enable_admin_toolbox: true` | convenience and diagnostic tools |

Application, DNS, MTA, and backup packages should belong to their own roles.
Add `pld_base_extra_packages` only for a temporary, clearly justified
exception.

## Custom software

Do not install individual local files with `rpm -Uvh`. The preferred order is:

1. prepare a spec and submit the package to PLD;
2. maintain a signed Poldek repository for private software;
3. declare the package name in the appropriate role and install it through
   Poldek.

This approach preserves dependencies, updates, and repeatable deployments.

## Removing legacy RPMs

The base list is not an allowlist for automatic cleanup. Before removing a
package, check its use in services, timers, cron jobs, and local scripts, then
run `rpm -e --test` and `poldek --test --erase`. Do not use `--nodeps` or
automatic “autoremove”. The plan for a read-only reporter of potentially
orphaned libraries is in [TODO-PLD.md](../TODO-PLD.md).
