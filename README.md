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

## Licencja

[Apache License 2.0](LICENSE) - wolne oprogramowanie w rozumieniu Free Software
Foundation i licencja otwarta zatwierdzona przez OSI. Możesz używać tego kodu
dowolnie, także komercyjnie, modyfikować go i rozprowadzać, również w projektach
zamkniętych. Jedyne wymagania to zachowanie informacji o prawach autorskich
i licencji oraz oznaczenie wprowadzonych zmian. Licencja zawiera też jawne
udzielenie praw patentowych przez współtwórców i jest zgodna z GPLv3, więc kod
może trafić także do projektów objętych copyleft.

```
Copyright 2026 SysGroup Sp. z o.o.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

---

LinuxLab jest częścią grupy [SysGroup Sp. z o.o.](https://sysgroup.pl)
