# linuxlab

Narzędzia i konfiguracje towarzyszące artykułom z bazy wiedzy
[linuxlab.pl](https://linuxlab.pl/baza-wiedzy.html). Wszystko, co tu trafia,
jest wcześniej uruchamiane na naszych maszynach, a nie przepisywane
z dokumentacji.

## Zawartość

| Ścieżka | Opis |
| --- | --- |
| [`scripts/power-probe.py`](scripts/power-probe.py) | Odczyt poboru mocy maszyny ze wszystkich dostępnych w Linuksie źródeł (IPMI, DCMI, hwmon, RAPL, bateria) wraz z zakresem, jaki obejmuje każde z nich. |
| [`docs/power-probe.md`](docs/power-probe.md) | Co który interfejs mierzy, na jakim sprzęcie działa, i czego nie da się odczytać. |
| [`tests/`](tests/) | Testy jednostkowe, uruchamiane bez dostępu do sprzętu. |

## Wymagania

Python 3.7 lub nowszy, bez zewnętrznych bibliotek. Liczniki RAPL i IPMI zwykle
wymagają uprawnień roota.

## Szybki start

```bash
git clone https://github.com/sysgroup/linuxlab.git
cd linuxlab

sudo ./scripts/power-probe.py -i 10      # pomiar w oknie 10 sekund
./scripts/power-probe.py --list          # tylko wykryte źródła
sudo ./scripts/power-probe.py --json     # wynik do monitoringu

python3 -m unittest discover -s tests -v # testy
```

## Powiązane artykuły

- [Laptop jako host KVM: jak obniżyliśmy zużycie energii o 40 procent](https://linuxlab.pl/zuzycie-energii-host-kvm-laptop.html)
- [Lab na osobnym hoście: od czystego Debiana 13 do jedenastu maszyn z Terraform](https://linuxlab.pl/lab-kvm-osobny-host-debian-13-terraform.html)
- [Lab do testów na Terraform i OpenTofu](https://linuxlab.pl/lab-testowy-terraform-opentofu-kvm.html)

---

LinuxLab jest częścią grupy [SysGroup Sp. z o.o.](https://sysgroup.pl)
