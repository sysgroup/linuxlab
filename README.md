# linuxlab

Narzędzia i konfiguracje towarzyszące artykułom z bazy wiedzy
[linuxlab.pl](https://linuxlab.pl/baza-wiedzy.html). Wszystko, co tu trafia,
jest wcześniej uruchamiane na naszych maszynach, a nie przepisywane
z dokumentacji.

## Zawartość

| Ścieżka | Opis |
| --- | --- |
| [`power-probe/`](power-probe/) | Odczyt poboru mocy maszyny ze wszystkich dostępnych w Linuksie źródeł (IPMI, DCMI, hwmon, RAPL, bateria) wraz z zakresem, jaki obejmuje każde z nich. W README: co który interfejs mierzy, na jakim sprzęcie działa i czego nie da się odczytać; testy działają bez dostępu do sprzętu. |
| [`terraform/`](terraform/) | Lab KVM opisany w Terraform: jedenaście maszyn (Debian, Ubuntu, pulpit, Proxmox Backup Server, k3s, Docker) w trzech warstwach, z cloud-init i poprawkami XML domen. Sprawdzony na Debianie 13 z libvirt 11.3. |
| [`ansible-pld/`](ansible-pld/) | Playbooki Ansible dla PLD Linux Th z systemd: profil pakietów instalowany przez Poldek, hardening (SSH, sysctl, fail2ban, auditd) i monitoring przez NRPE (Nagios Remote Plugin Executor). Dokumentacja po angielsku. Sprawdzone na PLD Th 3.0. |

## Wymagania

power-probe: Python 3.7 lub nowszy, bez zewnętrznych bibliotek. Liczniki RAPL
i IPMI zwykle wymagają uprawnień roota. Lab: libvirt z KVM oraz Terraform albo OpenTofu -
szczegóły w [`terraform/README.md`](terraform/README.md). PLD: Ansible z kolekcją
`community.general` - szczegóły w [`ansible-pld/README.md`](ansible-pld/README.md).

## Szybki start

```bash
git clone https://github.com/sysgroup/linuxlab.git
cd linuxlab/power-probe

sudo ./power-probe.py -i 10              # pomiar w oknie 10 sekund
./power-probe.py --list                  # tylko wykryte źródła
sudo ./power-probe.py --json             # wynik do monitoringu

python3 -m unittest discover -s tests -v # testy
```

Każdy katalog ma własne README z instrukcją; polecenia uruchamia się z jego
wnętrza.

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
