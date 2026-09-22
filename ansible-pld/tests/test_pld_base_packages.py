#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Regression contracts for the PLD base package profiles."""

from pathlib import Path
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "playbooks" / "roles" / "pld_base"
BUILD = ROOT / "playbooks" / "pld-build-sysbase.yml"
MONITORING = ROOT / "playbooks" / "pld-setup-monitoring.yml"


class PldBasePackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defaults = yaml.safe_load((ROLE / "defaults" / "main.yml").read_text())
        cls.main = yaml.safe_load((ROLE / "tasks" / "main.yml").read_text())
        cls.monitoring = yaml.safe_load(
            (ROLE / "tasks" / "monitoring.yml").read_text()
        )
        cls.install = yaml.safe_load((ROLE / "tasks" / "install.yml").read_text())
        cls.main_by_name = {task["name"]: task for task in cls.main}
        cls.install_by_name = {task["name"]: task for task in cls.install}

    def test_core_is_modern_and_has_no_legacy_services(self):
        core = self.defaults["pld_base_core_packages"]

        self.assertTrue(
            {"ca-certificates", "chrony", "curl", "man-db", "tmux"} <= set(core)
        )
        self.assertFalse(
            {"acpid", "bind", "exim", "logwatch", "ntpdate", "telnet", "tmpwatch"}
            & set(core)
        )

    def test_hardware_and_convenience_profiles_are_separate(self):
        self.assertEqual(
            self.defaults["pld_base_kvm_guest_packages"], ["qemu-guest-agent"]
        )
        self.assertEqual(self.defaults["pld_base_enable_irqbalance"], False)
        self.assertEqual(self.defaults["pld_base_enable_admin_toolbox"], False)
        self.assertFalse(
            {"ipmitool", "linux-firmware", "watchdog"}
            & set(self.defaults["pld_base_bare_metal_packages"])
        )

    def test_kvm_and_bare_metal_selection_is_fact_guarded(self):
        kvm = self.main_by_name["Packages :: add the KVM guest profile"]
        bare_metal = self.main_by_name["Packages :: add the bare-metal profile"]

        self.assertEqual(
            kvm["when"],
            [
                "ansible_facts['virtualization_role'] == 'guest'",
                "ansible_facts['virtualization_type'] == 'kvm'",
            ],
        )
        self.assertEqual(
            bare_metal["when"],
            "ansible_facts['virtualization_role'] == 'host'",
        )

    def test_all_missing_packages_use_the_poldek_wrapper_once(self):
        install = self.install_by_name[
            "Packages :: install selected exact RPM names with Poldek"
        ]

        self.assertEqual(
            install["pld_poldek"]["name"],
            "{{ _pld_base_requested_packages }}",
        )
        self.assertEqual(install["pld_poldek"]["state"], "present")
        self.assertNotIn("ansible.builtin.command", install)
        self.assertEqual(install["register"], "_pld_base_poldek_result")

    def test_monitoring_bootstraps_its_own_rpms_and_collects_facts(self):
        selected = self.monitoring[1]
        self.assertIn(
            "pld_base_core_packages + pld_base_monitoring_packages",
            selected["ansible.builtin.set_fact"]["_pld_base_requested_packages"],
        )

        monitoring_play = yaml.safe_load(MONITORING.read_text())[0]
        self.assertEqual(monitoring_play["gather_facts"], True)
        package_task = monitoring_play["tasks"][0]
        self.assertEqual(package_task["ansible.builtin.import_role"]["name"], "pld_base")
        self.assertEqual(
            package_task["ansible.builtin.import_role"]["tasks_from"], "monitoring"
        )

    def test_build_entrypoint_imports_the_base_role_under_a_narrow_tag(self):
        build_play = yaml.safe_load(BUILD.read_text())[0]
        package_task = build_play["tasks"][0]

        self.assertEqual(package_task["ansible.builtin.import_role"]["name"], "pld_base")
        self.assertEqual(package_task["tags"], ["packages", "pld-packages"])


if __name__ == "__main__":
    unittest.main()
