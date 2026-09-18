#!/usr/bin/env python3
"""power-probe.py - ile prądu bierze ta maszyna?

Wykrywa i odczytuje wszystkie dostępne w Linuksie źródła pomiaru mocy, od
najpełniejszego do najwęższego:

  1. IPMI - czujnik zasilacza ("PS1 Power In", "PSU1 Input Power") albo DCMI.
     Jedyne źródło, które podaje pobór CAŁEGO serwera, razem ze stratami
     zasilacza. Wymaga /dev/ipmi0, pakietu ipmitool i uprawnień roota.
  2. hwmon - czujniki mocy jądra (m.in. acpi_power_meter): power*_average
     i power*_input.
  3. RAPL psys - licznik mocy całej platformy w procesorze (laptopy i część
     desktopów). Nie obejmuje całego sprzętu: na ThinkPadzie T490 czytał
     0,7-1 W mniej niż moc faktycznie schodząca z płyty.
  4. RAPL package/dram/core/uncore - procesor i pamięć. Na serwerach zwykle
     jedyne dostępne źródło; to dolna granica poboru, a nie cały serwer.
  5. Bateria - moc rozładowania (tylko laptop w trybie na baterii).

Liczniki energii (RAPL) wymagają dwóch odczytów, dlatego skrypt mierzy przez
zadany czas. Czujniki chwilowe (IPMI, hwmon) odczytuje na końcu okna.

UWAGA na btop 1.3.2: przy baterii pokazuje energy_now/1e6, czyli zapas energii
w watogodzinach z etykietą "W". To nie jest pomiar mocy.

Użycie:
    power-probe.py                 # jeden pomiar, okno 5 s
    power-probe.py -i 60 -n 3      # trzy pomiary po 60 s
    power-probe.py --list          # tylko wykryte źródła, bez pomiaru
    power-probe.py --json          # wynik jako JSON (do monitoringu)

Bez zewnętrznych zależności: sama biblioteka standardowa, Python 3.7+.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

# Zakresy pomiaru - od tego zależy, jak wolno interpretować liczbę.
SCOPE_SYSTEM = "cały serwer (wejście zasilacza)"
SCOPE_PLATFORM = "platforma (CPU, pamięć, przetwornice)"
SCOPE_PACKAGE = "pakiet CPU"
SCOPE_DRAM = "pamięć"
SCOPE_PART = "część pakietu CPU"
SCOPE_BATTERY = "cała płyta (rozładowanie baterii)"

IPMI_WATT_SENSOR = re.compile(r"^\s*([^|]+?)\s*\|[^|]*\|[^|]*\|[^|]*\|\s*([\d.,]+)\s*Watts", re.M)
DCMI_READING = re.compile(r"Instantaneous power reading:\s*([\d.,]+)\s*Watts", re.I)
DCMI_STATE = re.compile(r"Power reading state is:\s*(\w+)", re.I)


def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read().strip()


def _to_float(text):
    return float(text.replace(",", "."))


class Source:
    """Jedno źródło pomiaru. `begin`/`end` obsługują liczniki energii."""

    kind = "sensor"

    def __init__(self, name, scope, note=""):
        self.name = name
        self.scope = scope
        self.note = note

    def begin(self):
        return None

    def end(self, started_at, elapsed):
        raise NotImplementedError


class EnergyCounter(Source):
    """Licznik energii w mikrodżulach (RAPL). Moc = przyrost / czas."""

    kind = "licznik energii"

    def __init__(self, name, scope, path, wrap_at, note=""):
        super().__init__(name, scope, note)
        self.path = path
        self.wrap_at = wrap_at

    def begin(self):
        return int(_read(self.path))

    def end(self, started_at, elapsed):
        value = int(_read(self.path))
        delta = value - started_at
        if delta < 0 and self.wrap_at:  # licznik przekręcił się w trakcie okna
            delta += self.wrap_at
        return delta / elapsed / 1_000_000


class HwmonSensor(Source):
    """Czujnik mocy jądra: wartość w mikrowatach."""

    def __init__(self, name, scope, path, note=""):
        super().__init__(name, scope, note)
        self.path = path

    def end(self, started_at, elapsed):
        return int(_read(self.path)) / 1_000_000


class BatterySensor(Source):
    """Moc rozładowania baterii: pełny pobór płyty, ale tylko na baterii."""

    def __init__(self, name, base):
        super().__init__(name, SCOPE_BATTERY)
        self.base = base

    def end(self, started_at, elapsed):
        status = _read(os.path.join(self.base, "status"))
        if status != "Discharging":
            raise RuntimeError(f"bateria nie rozładowuje się (status: {status})")
        return int(_read(os.path.join(self.base, "power_now"))) / 1_000_000


class IpmiSensor(Source):
    """Czujnik zasilacza z BMC - jedyny pomiar całego serwera."""

    def __init__(self, name, note=""):
        super().__init__(name, SCOPE_SYSTEM, note)

    def end(self, started_at, elapsed):
        for sensor_name, value in IPMI_WATT_SENSOR.findall(_ipmitool("sdr", "elist", "full")):
            if sensor_name.strip() == self.name:
                return _to_float(value)
        raise RuntimeError("czujnik zniknął z listy IPMI")


class DcmiReading(Source):
    """DCMI: standardowy odczyt mocy platformy przez BMC."""

    def __init__(self, note=""):
        super().__init__("DCMI power reading", SCOPE_SYSTEM, note)

    def end(self, started_at, elapsed):
        output = _ipmitool("dcmi", "power", "reading")
        match = DCMI_READING.search(output)
        if not match:
            raise RuntimeError("brak odczytu w odpowiedzi DCMI")
        return _to_float(match.group(1))


def _ipmitool(*args):
    result = subprocess.run(
        ["ipmitool", *args], capture_output=True, text=True, timeout=20, check=False
    )
    if result.returncode != 0 and not result.stdout.strip():
        raise RuntimeError((result.stderr or "ipmitool zwrócił błąd").strip().splitlines()[-1])
    return result.stdout


def discover_rapl():
    sources = []
    for domain in sorted(glob.glob("/sys/class/powercap/intel-rapl*:*")):
        energy = os.path.join(domain, "energy_uj")
        name_file = os.path.join(domain, "name")
        if not (os.path.exists(energy) and os.path.exists(name_file)):
            continue
        try:
            name = _read(name_file)
            wrap_at = int(_read(os.path.join(domain, "max_energy_range_uj")))
        except OSError:
            continue
        if not os.access(energy, os.R_OK):
            sources.append((f"RAPL {name}", "RAPL", "energy_uj czytelny tylko dla roota"))
            continue
        scope = {
            "psys": SCOPE_PLATFORM,
            "dram": SCOPE_DRAM,
        }.get(name, SCOPE_PACKAGE if name.startswith("package") else SCOPE_PART)
        note = "nie obejmuje całego sprzętu" if name == "psys" else ""
        node = os.path.basename(domain)
        label = f"RAPL {name}" if node.startswith("intel-rapl:") else f"RAPL {name} ({node})"
        sources.append(EnergyCounter(label, scope, energy, wrap_at, note))
    return sources


def discover_hwmon():
    sources = []
    for path in sorted(glob.glob("/sys/class/hwmon/hwmon*/power*_average")
                       + glob.glob("/sys/class/hwmon/hwmon*/power*_input")):
        chip = os.path.dirname(path)
        try:
            label = _read(os.path.join(chip, "name"))
        except OSError:
            label = os.path.basename(chip)
        if not os.access(path, os.R_OK):
            continue
        # Bateria wystawia moc takze przez hwmon - liczymy ja raz, w discover_battery().
        if re.fullmatch(r"BAT\d*", label):
            continue
        sources.append(HwmonSensor(f"hwmon {label} ({os.path.basename(path)})",
                                   SCOPE_PLATFORM, path))
    return sources


def discover_battery():
    sources = []
    for base in sorted(glob.glob("/sys/class/power_supply/BAT*")):
        if os.path.exists(os.path.join(base, "power_now")):
            sources.append(BatterySensor(f"bateria {os.path.basename(base)}", base))
    return sources


def discover_ipmi():
    sources, problems = [], []
    if not glob.glob("/dev/ipmi*"):
        return sources, problems
    if not shutil.which("ipmitool"):
        problems.append(("ipmitool", "IPMI", "jest /dev/ipmi0, ale brakuje pakietu ipmitool"))
        return sources, problems
    try:
        listing = _ipmitool("sdr", "elist", "full")
    except Exception as exc:  # brak uprawnień, brak BMC, timeout
        problems.append(("ipmitool", "IPMI", str(exc)))
        return sources, problems
    for name, _value in IPMI_WATT_SENSOR.findall(listing):
        sources.append(IpmiSensor(name.strip(), "czujnik zasilacza z BMC"))
    try:
        dcmi = _ipmitool("dcmi", "power", "reading")
        state = DCMI_STATE.search(dcmi)
        reading = DCMI_READING.search(dcmi)
        if reading and _to_float(reading.group(1)) > 0:
            sources.append(DcmiReading())
        elif state and state.group(1).lower() != "activated":
            problems.append(("DCMI", "IPMI", f"odczyt nieaktywny na tej płycie ({state.group(1)})"))
        elif reading:
            problems.append(("DCMI", "IPMI", "płyta zwraca 0 W - brak pomiaru"))
    except Exception as exc:
        problems.append(("DCMI", "IPMI", str(exc)))
    return sources, problems


def discover():
    sources, problems = discover_ipmi()
    for item in discover_hwmon() + discover_rapl() + discover_battery():
        if isinstance(item, tuple):
            problems.append(item)
        else:
            sources.append(item)
    return sources, problems


def measure(sources, interval):
    started = {}
    for source in sources:
        try:
            started[source] = source.begin()
        except Exception as exc:
            started[source] = exc
    start = time.monotonic()
    time.sleep(interval)
    elapsed = time.monotonic() - start

    results = []
    for source in sources:
        if isinstance(started[source], Exception):
            results.append((source, None, str(started[source])))
            continue
        try:
            results.append((source, source.end(started[source], elapsed), None))
        except Exception as exc:
            results.append((source, None, str(exc)))
    return results, elapsed


def print_table(results, elapsed, problems):
    width = max([len(source.name) for source, _, _ in results] + [12])
    print(f"{'źródło'.ljust(width)}  {'moc':>9}   zakres pomiaru")
    print("-" * (width + 12 + 34))
    for source, watts, error in results:
        if watts is None:
            print(f"{source.name.ljust(width)}  {'-':>9}   {error}")
        else:
            note = f" - {source.note}" if source.note else ""
            print(f"{source.name.ljust(width)}  {watts:8.2f} W   {source.scope}{note}")
    for name, kind, reason in problems:
        print(f"{name.ljust(width)}  {'-':>9}   {kind}: {reason}")
    print(f"\nokno pomiaru: {elapsed:.1f} s")


def main():
    parser = argparse.ArgumentParser(
        description="Odczyt poboru mocy maszyny ze wszystkich dostępnych źródeł.",
        epilog="Liczniki RAPL i IPMI zwykle wymagają roota.",
    )
    parser.add_argument("-i", "--interval", type=float, default=5.0,
                        help="długość okna pomiaru w sekundach (domyślnie 5)")
    parser.add_argument("-n", "--count", type=int, default=1,
                        help="ile pomiarów wykonać (domyślnie 1, 0 = bez końca)")
    parser.add_argument("--list", action="store_true",
                        help="wypisz wykryte źródła i zakończ")
    parser.add_argument("--json", action="store_true",
                        help="wynik w formacie JSON")
    args = parser.parse_args()

    sources, problems = discover()

    if args.list:
        for source in sources:
            print(f"{source.name}\t{source.kind}\t{source.scope}")
        for name, kind, reason in problems:
            print(f"{name}\t-\t{kind}: {reason}", file=sys.stderr)
        return 0 if sources else 1

    if not sources:
        print("Nie znaleziono żadnego źródła pomiaru mocy.", file=sys.stderr)
        for name, kind, reason in problems:
            print(f"  {name}: {reason}", file=sys.stderr)
        if os.geteuid() != 0:
            print("  Spróbuj ponownie jako root: liczniki RAPL i IPMI są zwykle "
                  "niedostępne dla zwykłego użytkownika.", file=sys.stderr)
        return 1

    iteration = 0
    while args.count == 0 or iteration < args.count:
        results, elapsed = measure(sources, args.interval)
        if args.json:
            print(json.dumps({
                "host": os.uname().nodename,
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "interval_s": round(elapsed, 3),
                "sources": [
                    {"name": source.name, "scope": source.scope, "kind": source.kind,
                     "watts": None if watts is None else round(watts, 2), "error": error}
                    for source, watts, error in results
                ],
                "problems": [{"name": n, "kind": k, "reason": r} for n, k, r in problems],
            }, ensure_ascii=False))
        else:
            if iteration:
                print()
            print_table(results, elapsed, problems)
        sys.stdout.flush()
        iteration += 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
