#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Test the PLD repository boundary."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
PUBLIC_INVENTORY = ROOT / "inventory" / "local.example.yml"
DEFAULT_INVENTORY = ROOT / "inventory" / "hosts.yml"


class PldStandaloneTests(unittest.TestCase):
    def test_entrypoints_do_not_import_debian_roles(self):
        for filename in (
            "pld-build-sysbase.yml",
            "pld-setup-monitoring.yml",
            "pld-hardening.yml",
        ):
            play = yaml.safe_load((ROOT / "playbooks" / filename).read_text())[0]
            for task in play.get("tasks", []):
                role = task.get("ansible.builtin.import_role", {}).get("name")
                self.assertNotIn(role, {"system", "monitoring"}, filename)

    def test_public_inventory_example_has_no_central_nagios_projection(self):
        inventory = yaml.safe_load(PUBLIC_INVENTORY.read_text(encoding="utf-8"))
        host = inventory["all"]["children"]["pld"]["hosts"]["pld.example.net"]
        self.assertFalse(
            {
                "nagios_address",
                "nagios_client",
                "host_services",
                "nagios_excluded_checks",
                "domains",
                "nagios_rbl",
            }
            & set(host)
        )

    def test_default_inventory_has_no_deployable_hosts(self):
        inventory = yaml.safe_load(DEFAULT_INVENTORY.read_text(encoding="utf-8"))
        self.assertEqual(inventory["all"]["children"]["pld"]["hosts"], {})

    def test_roles_do_not_read_central_nagios_variables(self):
        role_text = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "playbooks" / "roles").rglob("*")
            if path.is_file() and "__pycache__" not in path.parts
        )
        self.assertNotIn("nagios_host_name", role_text)

    def test_monitoring_subsystem_tags_do_not_select_the_whole_role(self):
        play = yaml.safe_load(
            (ROOT / "playbooks" / "pld-setup-monitoring.yml").read_text(
                encoding="utf-8"
            )
        )[0]
        monitoring_import = next(
            task
            for task in play["tasks"]
            if task.get("ansible.builtin.import_role", {}).get("name")
            == "pld_monitoring"
        )
        self.assertEqual(monitoring_import["tags"], ["monitoring"])


if __name__ == "__main__":
    unittest.main()
