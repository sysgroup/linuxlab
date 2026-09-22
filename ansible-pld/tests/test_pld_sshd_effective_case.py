#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Regression test for OpenSSH 10 effective-configuration casing on PLD."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VERIFY = ROOT / "playbooks" / "roles" / "pld_hardening" / "tasks" / "verify.yml"


class PldSshdEffectiveCaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.verify = VERIFY.read_text(encoding="utf-8")

    def test_effective_output_is_normalized_before_assertions(self):
        self.assertIn(
            '_pld_sshd_effective_lower: "{{ _pld_sshd_effective.stdout | lower }}"',
            self.verify,
        )
        for directive in (
            "permitrootlogin no",
            "passwordauthentication no",
            "kbdinteractiveauthentication no",
            "pubkeyauthentication yes",
        ):
            with self.subTest(directive=directive):
                self.assertIn(
                    f"'{directive}' in _pld_sshd_effective_lower", self.verify
                )
                self.assertNotRegex(
                    self.verify,
                    re.compile(
                        rf"'{directive}[^']*' in _pld_sshd_effective[.]stdout\\b"
                    ),
                )

if __name__ == "__main__":
    unittest.main()
