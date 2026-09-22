#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
"""Behavior tests for the custom NRPE plugins shipped with PLD."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
PLUGINS = ROOT / "playbooks" / "roles" / "pld_monitoring" / "files"


def run_plugin(name, *arguments):
    return subprocess.run(
        [sys.executable, str(PLUGINS / name), *map(str, arguments)],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )


class PldMonitoringPluginTests(unittest.TestCase):
    def test_reboot_plugin_latches_then_recovers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            boot_id = root / "boot_id"
            proc_stat = root / "stat"
            boot_id.write_text("boot-a\n", encoding="utf-8")
            proc_stat.write_text(
                f"cpu 1 2 3 4\nbtime {int(time.time()) - 120}\n",
                encoding="utf-8",
            )
            arguments = (
                "--state-dir", state,
                "--boot-id-file", boot_id,
                "--proc-stat", proc_stat,
                "--hostname", "pld-test",
                "--alert-window", "60",
            )
            self.assertEqual(run_plugin("check_reboot", *arguments).returncode, 0)
            boot_id.write_text("boot-b\n", encoding="utf-8")
            detected = run_plugin("check_reboot", *arguments)
            self.assertEqual(detected.returncode, 1, detected.stdout + detected.stderr)
            self.assertIn("server pld-test restarted", detected.stdout)

    def test_oom_plugin_detects_kernel_events(self):
        with tempfile.TemporaryDirectory() as temporary:
            journalctl = Path(temporary) / "journalctl"
            journalctl.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' 'kernel: Out of memory: Killed process 123 (worker)'\n",
                encoding="utf-8",
            )
            journalctl.chmod(0o755)
            result = run_plugin(
                "check_oom_killer",
                "--hostname", "pld-test",
                "--lookback-minutes", "60",
                "--critical-count", "3",
                "--journalctl", journalctl,
            )
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("1 OOM-killer event", result.stdout)

    def test_load_and_memory_plugins_have_stable_thresholds(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            loadavg = root / "loadavg"
            loadavg.write_text("5 5 5 1/100 123\n", encoding="utf-8")
            load = run_plugin(
                "check_load_per_cpu",
                "--loadavg-file", loadavg,
                "--cpu-count", "2",
                "--hostname", "pld-test",
                "--warning", "1,1,1",
                "--critical", "2,2,2",
            )
            self.assertEqual(load.returncode, 2, load.stdout + load.stderr)

            meminfo = root / "meminfo"
            meminfo.write_text(
                "MemTotal:       1000000 kB\n"
                "MemAvailable:    50000 kB\n"
                "SwapTotal:       100000 kB\n"
                "SwapFree:         50000 kB\n",
                encoding="utf-8",
            )
            memory = run_plugin(
                "check_memory_available",
                "--meminfo-file", meminfo,
                "--hostname", "pld-test",
                "--warning-available", "15",
                "--critical-available", "8",
            )
            self.assertEqual(memory.returncode, 2, memory.stdout + memory.stderr)

    def test_poldek_cache_plugin_reports_update_and_stale_states(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "status"
            updates = root / "updates"
            now = int(time.time())
            arguments = (
                "--state-file", state,
                "--updates-file", updates,
                "--hostname", "pld-test",
                "--now", str(now),
            )
            updates.write_text("kernel\n", encoding="utf-8")
            state.write_text(
                f"timestamp={now}\nstatus=ok\ncount=1\nreason=none\n",
                encoding="utf-8",
            )
            warning = run_plugin("check_poldek_updates", *arguments)
            self.assertEqual(warning.returncode, 1, warning.stdout + warning.stderr)

            state.write_text(
                f"timestamp={now - 31 * 3600}\nstatus=ok\ncount=1\nreason=none\n",
                encoding="utf-8",
            )
            stale = run_plugin("check_poldek_updates", *arguments)
            self.assertEqual(stale.returncode, 3, stale.stdout + stale.stderr)

    def test_systemd_restart_loop_is_not_hidden(self):
        with tempfile.TemporaryDirectory() as temporary:
            systemctl = Path(temporary) / "systemctl"
            systemctl.write_text(
                "#!/bin/sh\n"
                'case "$1" in\n'
                "list-units)\n"
                "  printf '%s\\n' 'nginx.service loaded activating auto-restart nginx'\n"
                "  ;;\n"
                "show)\n"
                "  printf '%s\\n' '11759'\n"
                "  ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            systemctl.chmod(0o755)
            result = run_plugin(
                "check_systemd_units", "--systemctl", systemctl
            )
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("restart loop", result.stdout)

    def test_disk_plugin_is_valid_bash(self):
        result = subprocess.run(
            ["bash", "-n", str(PLUGINS / "check_all_disks")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
