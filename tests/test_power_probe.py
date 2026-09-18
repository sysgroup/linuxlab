#!/usr/bin/env python3
"""Testy parsowania i liczenia w scripts/power-probe.py (bez sprzętu)."""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("power_probe", ROOT / "scripts" / "power-probe.py")
power_probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(power_probe)


# Prawdziwe wyjście `ipmitool sdr elist full` z serwera na płycie Intel S1200BTL.
SDR_WITH_PSU = """BMC Board TEMP   | 20h | ok  |  7.0 | 33 degrees C
SysFan2          | 31h | ok  | 29.1 | 3960 RPM
PS1 Power In     | 54h | ok  | 10.1 | 84 Watts
PS1 Temperature  | 5Ch | ok  | 10.1 | 30 degrees C
BB +12.0V        | D0h | ok  |  7.1 | 12,03 Volts
"""

# Supermicro z Xeonem D: same temperatury i napięcia, żadnego czujnika mocy.
SDR_WITHOUT_PSU = """CPU Temp         | 01h | ok  |  3.1 | 36 degrees C
12V              | 30h | ok  |  7.17 | 12,06 Volts
Chassis Intru    | AAh | ok  | 23.1 |
"""

DCMI_DEACTIVATED = """
    Instantaneous power reading:                     0 Watts
    Minimum during sampling period:                  0 Watts
    Power reading state is:                   deactivated
"""

DCMI_ACTIVE = """
    Instantaneous power reading:                   145 Watts
    Power reading state is:                   activated
"""


class IpmiParsingTests(unittest.TestCase):
    def test_finds_psu_input_power(self):
        found = power_probe.IPMI_WATT_SENSOR.findall(SDR_WITH_PSU)
        self.assertEqual([(name.strip(), value) for name, value in found], [("PS1 Power In", "84")])

    def test_ignores_temperatures_and_volts(self):
        self.assertEqual(power_probe.IPMI_WATT_SENSOR.findall(SDR_WITHOUT_PSU), [])

    def test_dcmi_reading_and_state(self):
        self.assertEqual(power_probe.DCMI_READING.search(DCMI_ACTIVE).group(1), "145")
        self.assertEqual(
            power_probe.DCMI_STATE.search(DCMI_DEACTIVATED).group(1), "deactivated"
        )

    def test_decimal_comma_is_accepted(self):
        # ipmitool w polskiej lokalizacji drukuje "12,06 Volts" / "84,5 Watts".
        self.assertAlmostEqual(power_probe._to_float("84,5"), 84.5)


class EnergyCounterTests(unittest.TestCase):
    def _counter(self, value, wrap_at=262143328850):
        handle, path = tempfile.mkstemp()
        os.write(handle, str(value).encode())
        os.close(handle)
        self.addCleanup(os.unlink, path)
        return power_probe.EnergyCounter("test", power_probe.SCOPE_PACKAGE, path, wrap_at), path

    def test_power_is_energy_delta_over_time(self):
        counter, path = self._counter(0)
        Path(path).write_text("10000000")  # 10 J w 10 s = 1 W
        self.assertAlmostEqual(counter.end(0, 10.0), 1.0)

    def test_counter_wrap_is_handled(self):
        wrap = 1000000
        counter, path = self._counter(0, wrap_at=wrap)
        Path(path).write_text("100000")  # licznik przekręcił się z 900000
        self.assertAlmostEqual(counter.end(900000, 1.0), 0.2)

    def test_negative_delta_without_wrap_limit_stays_negative(self):
        # Bez znanego zakresu nie zgadujemy - lepiej pokazać nonsens niż zmyślić.
        counter, path = self._counter(0, wrap_at=0)
        Path(path).write_text("5")
        self.assertLess(counter.end(100, 1.0), 0)


class BatteryTests(unittest.TestCase):
    def _battery(self, status, power_uw):
        base = tempfile.mkdtemp()
        self.addCleanup(lambda: [os.unlink(os.path.join(base, f)) for f in os.listdir(base)]
                        and os.rmdir(base))
        Path(base, "status").write_text(status)
        Path(base, "power_now").write_text(str(power_uw))
        return power_probe.BatterySensor("bateria BAT0", base)

    def test_reads_power_while_discharging(self):
        self.assertAlmostEqual(self._battery("Discharging", 3390000).end(None, 5.0), 3.39)

    def test_refuses_when_not_discharging(self):
        # Na zasilaczu power_now bywa zerem - to nie jest pomiar poboru maszyny.
        with self.assertRaises(RuntimeError):
            self._battery("Full", 0).end(None, 5.0)


class ScopeTests(unittest.TestCase):
    def test_every_scope_says_what_it_covers(self):
        for scope in (power_probe.SCOPE_SYSTEM, power_probe.SCOPE_PLATFORM,
                      power_probe.SCOPE_PACKAGE, power_probe.SCOPE_DRAM,
                      power_probe.SCOPE_BATTERY):
            self.assertTrue(scope.strip())
        # Tylko czujnik zasilacza obejmuje CALY serwer - reszta jest wezsza.
        self.assertIn("cały serwer", power_probe.SCOPE_SYSTEM)
        self.assertNotIn("cały serwer", power_probe.SCOPE_PLATFORM)


if __name__ == "__main__":
    unittest.main()
