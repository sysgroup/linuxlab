#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Regression contract for PLD sysctl convergence and verification."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "playbooks" / "roles" / "pld_hardening"
SYSCTL = ROLE / "tasks" / "sysctl.yml"
VERIFY = ROLE / "tasks" / "verify.yml"


class PldHardeningSysctlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sysctl = yaml.safe_load(SYSCTL.read_text(encoding="utf-8"))
        cls.verify = yaml.safe_load(VERIFY.read_text(encoding="utf-8"))
        cls.sysctl_by_name = {task["name"]: task for task in cls.sysctl}
        cls.verify_by_name = {task["name"]: task for task in cls.verify}

    def test_sysctl_is_flushed_immediately_after_deploy(self):
        names = [task["name"] for task in self.sysctl]
        deploy = "Sysctl :: deploy PLD hardening values"
        legacy = "Sysctl :: remove files left by an earlier version of this role"
        flush = "Sysctl :: apply pending values before verification"

        # Only the legacy cleanup, which notifies the same handler, may sit
        # between the deploy and the flush.
        self.assertEqual(names.index(legacy), names.index(deploy) + 1)
        self.assertEqual(names.index(flush), names.index(legacy) + 1)
        self.assertEqual(
            self.sysctl_by_name[flush]["ansible.builtin.meta"], "flush_handlers"
        )

    def test_preflight_batches_all_sysctl_keys_in_one_command(self):
        task = self.sysctl_by_name["Sysctl :: verify every requested kernel key exists"]

        self.assertNotIn("loop", task)
        self.assertEqual(
            task["ansible.builtin.command"]["argv"],
            "{{ ['sysctl', '-n'] + (_pld_sysctl_items | map(attribute='key') | list) }}",
        )
        self.assertEqual(
            task["vars"]["_pld_sysctl_items"],
            "{{ pld_sysctl_hardening | dict2items | sort(attribute='key') }}",
        )

    def test_verification_batches_values_and_uses_one_assertion(self):
        read = self.verify_by_name["Verify :: read effective sysctl values"]
        check = self.verify_by_name["Verify :: assert effective sysctl values"]

        self.assertNotIn("loop", read)
        self.assertNotIn("loop", check)
        self.assertEqual(
            read["ansible.builtin.command"]["argv"],
            "{{ ['sysctl', '-n'] + (_pld_sysctl_items | map(attribute='key') | list) }}",
        )
        self.assertEqual(len(check["ansible.builtin.assert"]["that"]), 1)
        self.assertIn("_pld_sysctl_effective.stdout_lines", check["ansible.builtin.assert"]["that"][0])


if __name__ == "__main__":
    unittest.main()
