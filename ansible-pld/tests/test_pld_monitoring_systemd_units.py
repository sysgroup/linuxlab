#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Regression contract for the NRPE systemd-units task."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
TASKS = ROOT / "playbooks" / "roles" / "pld_monitoring" / "tasks" / "systemd-units.yml"
DEFAULTS = ROOT / "playbooks" / "roles" / "pld_monitoring" / "defaults" / "main.yml"


class MonitoringSystemdUnitsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tasks = yaml.safe_load(TASKS.read_text(encoding="utf-8"))
        cls.defaults = yaml.safe_load(DEFAULTS.read_text(encoding="utf-8"))
        deploy = next(
            task for task in tasks
            if task["name"] == "Nrpe systemd :: deploy when NRPE is present"
        )
        cls.variables = deploy["vars"]
        cls.tasks_by_name = {task["name"]: task for task in deploy["block"]}

    def test_pld_nrpe_paths_are_role_defaults(self):
        self.assertEqual(self.defaults["nrpe_service_name"], "nrpe")
        self.assertEqual(self.defaults["nrpe_runuser_path"], "/bin/runuser")

    def test_local_verification_reuses_the_nrpe_plugin_arguments(self):
        """A staged --warn-only run must verify the same command NRPE serves."""
        self.assertIn("_nrpe_systemd_plugin_args", self.variables)

        command_definition = self.tasks_by_name[
            "Nrpe systemd :: NRPE command definition"
        ]
        verification = self.tasks_by_name[
            "Nrpe systemd :: verify through the NRPE execution path"
        ]

        self.assertIn(
            "_nrpe_systemd_plugin_args | join(' ')",
            command_definition["ansible.builtin.copy"]["content"],
        )
        self.assertIn(
            "+ _nrpe_systemd_plugin_args",
            verification["ansible.builtin.command"]["argv"],
        )


if __name__ == "__main__":
    unittest.main()
