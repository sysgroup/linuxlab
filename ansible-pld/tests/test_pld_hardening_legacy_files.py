#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Regression contract for removing files left by earlier role versions."""

from pathlib import Path
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "playbooks" / "roles" / "pld_hardening"

# component task file -> (directory prefix in the select filter, handler)
COMPONENTS = {
    "sshd.yml": ("^/etc/ssh/sshd_config[.]d/", "Reload PLD sshd"),
    "sysctl.yml": ("^/etc/sysctl[.]d/", "Reload PLD hardening sysctl"),
    "fail2ban.yml": ("^/etc/fail2ban/jail[.]d/", "Reload PLD fail2ban"),
    "auditd.yml": ("^/etc/audit/rules[.]d/", "Load PLD audit rules"),
}


def flatten(tasks):
    for task in tasks:
        yield task
        for key in ("block", "rescue", "always"):
            yield from flatten(task.get(key, []))


def load(name):
    return list(flatten(yaml.safe_load((ROLE / "tasks" / name).read_text(encoding="utf-8"))))


class PldHardeningLegacyFilesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defaults = yaml.safe_load((ROLE / "defaults" / "main.yml").read_text(encoding="utf-8"))
        cls.main = load("main.yml")
        guard = [t for t in cls.main if t.get("loop") == "{{ pld_hardening_legacy_files }}"]
        assert len(guard) == 1
        cls.guard = guard[0]
        cls.path_pattern = re.compile(cls.guard["ansible.builtin.assert"]["that"][0].split("'")[1])

    def test_feature_is_opt_in(self):
        self.assertEqual(self.defaults["pld_hardening_legacy_files"], [])

    def test_guard_runs_for_every_tag_before_any_component(self):
        self.assertIn("always", self.guard["tags"])
        names = [t["name"] for t in self.main]
        packages = names.index("PLD packages")
        self.assertLess(names.index(self.guard["name"]), packages)

    def test_guard_accepts_old_file_names(self):
        for path in (
            "/etc/ssh/sshd_config.d/00-old-hardening.conf",
            "/etc/sysctl.d/60-old-hardening.conf",
            "/etc/fail2ban/jail.d/99-old-hardening.local",
            "/etc/audit/rules.d/30-old-hardening.rules",
        ):
            self.assertRegex(path, self.path_pattern)

    def test_guard_rejects_anything_outside_the_component_directories(self):
        for path in (
            "/etc/ssh/sshd_config",
            "/etc/sysctl.d",
            "/etc/sysctl.d/",
            "/etc/sysctl.d/..",
            "/etc/sysctl.d/.hidden",
            "/etc/sysctl.d/../passwd",
            "/etc/fail2ban/jail.d/sub/file.local",
            "/etc/audit/rules.d/*.rules",
            "/etc/fail2ban/jail.conf",
            "relative/60-old.conf",
        ):
            self.assertNotRegex(path, self.path_pattern)

    def test_guard_protects_managed_files(self):
        managed = self.guard["vars"]["_pld_hardening_managed_files"]
        rendered = set()
        for name in COMPONENTS:
            for task in load(name):
                for module in ("ansible.builtin.template", "ansible.builtin.copy"):
                    dest = task.get(module, {}).get("dest", "")
                    if dest.startswith("/etc/"):
                        rendered.add(dest)
        self.assertEqual(set(managed), rendered)

    def test_each_component_removes_only_its_own_directory(self):
        for name, (prefix, handler) in COMPONENTS.items():
            with self.subTest(component=name):
                removals = [
                    t for t in load(name)
                    if "pld_hardening_legacy_files" in str(t.get("loop", ""))
                ]
                self.assertEqual(len(removals), 1)
                task = removals[0]
                self.assertEqual(task["ansible.builtin.file"]["state"], "absent")
                self.assertIn(f"select('match', '{prefix}')", task["loop"])
                self.assertEqual(task["notify"], handler)

    def test_removal_follows_the_new_file(self):
        for name in COMPONENTS:
            with self.subTest(component=name):
                tasks = load(name)
                removal = next(
                    i for i, t in enumerate(tasks)
                    if "pld_hardening_legacy_files" in str(t.get("loop", ""))
                )
                deploys = [
                    i for i, t in enumerate(tasks)
                    if str(t.get("ansible.builtin.template", {}).get("dest", "")).startswith("/etc/")
                ]
                self.assertTrue(deploys)
                self.assertGreater(removal, max(deploys))


if __name__ == "__main__":
    unittest.main()
