#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Static contract tests for the local, intentionally narrow Poldek module."""

import ast
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "plugins" / "modules" / "pld_poldek.py"


class PldPoldekModuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = MODULE.read_text(encoding="utf-8")
        ast.parse(cls.source)

    def test_reads_rpm_db_once_and_groups_missing_packages(self):
        self.assertIn('query = [rpm, "-qa", "--qf", "%{NAME}\\\\n"]', self.source)
        self.assertIn("missing = [name for name in requested if name not in installed]", self.source)
        self.assertIn('command.extend(["--install", *missing])', self.source)

    def test_check_mode_uses_poldek_test(self):
        self.assertIn("if module.check_mode:", self.source)
        self.assertIn('command.append("--test")', self.source)

    def test_wrapper_refuses_unsafe_or_destructive_api(self):
        self.assertIn("_PACKAGE_NAME", self.source)
        self.assertIn('choices": ["present"]', self.source)
        self.assertNotIn("state: absent", self.source)


if __name__ == "__main__":
    unittest.main()
