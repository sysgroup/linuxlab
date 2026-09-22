#!/usr/bin/python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Install exact PLD RPM names through one idempotent Poldek transaction."""

DOCUMENTATION = r"""
---
module: pld_poldek
short_description: Install exact RPM names with Poldek
description:
  - Reads the local RPM database once and installs all missing exact package names
    with one Poldek transaction.
  - Check mode validates that transaction with C(poldek --test).
  - This module deliberately has no erase operation.
options:
  name:
    description:
      - Exact RPM package names to install.
      - Version expressions, capabilities and globs are intentionally rejected.
    type: list
    elements: str
    required: true
  state:
    description:
      - Desired package state.
    type: str
    choices: [present]
    default: present
author:
  - LinuxLab.pl (https://linuxlab.pl)
"""

EXAMPLES = r"""
- name: Install the PLD base profile in one transaction
  pld_poldek:
    name:
      - chrony
      - syslog-ng
      - qemu-guest-agent
    state: present
"""

RETURN = r"""
requested:
  description: Normalized requested package names.
  returned: always
  type: list
  elements: str
missing:
  description: Requested packages absent from the local RPM database before the transaction.
  returned: always
  type: list
  elements: str
command:
  description: Poldek command that was executed, if a package was missing.
  returned: when packages are missing
  type: list
  elements: str
"""

import re

from ansible.module_utils.basic import AnsibleModule


_PACKAGE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.-]*$")


def fail_for_command(module, description, command, rc, stdout, stderr):
    module.fail_json(
        msg=f"{description} failed",
        command=command,
        rc=rc,
        stdout=stdout,
        stderr=stderr,
    )


def main():
    module = AnsibleModule(
        argument_spec={
            "name": {"type": "list", "elements": "str", "required": True},
            "state": {"type": "str", "choices": ["present"], "default": "present"},
        },
        supports_check_mode=True,
    )

    requested = sorted(set(module.params["name"]))
    invalid = [name for name in requested if not _PACKAGE_NAME.fullmatch(name)]
    if invalid:
        module.fail_json(
            msg=(
                "name accepts exact RPM names only; capabilities, versions, "
                f"globs and unsafe values are not supported: {', '.join(invalid)}"
            )
        )
    if not requested:
        module.fail_json(msg="name must contain at least one exact RPM name")

    rpm = module.get_bin_path("rpm", required=True)
    poldek = module.get_bin_path("poldek", required=True)
    query = [rpm, "-qa", "--qf", "%{NAME}\\n"]
    rc, stdout, stderr = module.run_command(query)
    if rc != 0:
        fail_for_command(module, "RPM database query", query, rc, stdout, stderr)

    installed = set(stdout.splitlines())
    missing = [name for name in requested if name not in installed]
    result = {"changed": bool(missing), "requested": requested, "missing": missing}
    if not missing:
        module.exit_json(**result)

    command = [poldek, "--noask"]
    if module.check_mode:
        command.append("--test")
    command.extend(["--install", *missing])
    rc, stdout, stderr = module.run_command(command)
    if rc != 0:
        fail_for_command(module, "Poldek transaction", command, rc, stdout, stderr)

    result.update(command=command, stdout=stdout, stderr=stderr)
    module.exit_json(**result)


if __name__ == "__main__":
    main()
