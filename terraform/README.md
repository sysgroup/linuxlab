# Lab KVM opisany w Terraform

Jedenaście maszyn wirtualnych na libvirt i KVM (od angielskiego *Kernel-based
Virtual Machine*), stawianych i odtwarzanych jednym poleceniem: sześć systemów
testowych (Debian 11, 12, 13, Ubuntu 22.04, 24.04, 26.04) i pięć maszyn
usługowych (pulpit KDE, Proxmox Backup Server, k3s pod AWX, Docker,
monitoring). To ten sam kod, na którym działa nasz lab. Opisują go artykuły
[Lab do testów na Terraform i OpenTofu](https://linuxlab.pl/lab-testowy-terraform-opentofu-kvm.html)
oraz [Lab na osobnym hoście](https://linuxlab.pl/lab-kvm-osobny-host-debian-13-terraform.html).

Sprawdzone na: Debian 13.7, libvirt 11.3.0, QEMU 10.0.13, Terraform 1.16,
provider `dmacvicar/libvirt` 0.8.3. Wcześniej ten sam kod działał na Ubuntu
24.04 z libvirt 10.0.0.

## Struktura

```
terraform/
├── base/            # pula obrazów bazowych, obrazy, sieć NAT "lab"   -> osobny stan
├── testboxes/       # deb11-13, ubu2204/2404/2604                    -> osobny stan
├── infra/           # kdev, pbs, awx, docker, mon                    -> osobny stan
├── modules/vm-group # wspólny moduł maszyn: dyski, cloud-init, domeny, XSLT
├── scripts/         # przygotowanie obrazów bazowych
└── Makefile         # skróty: base, apply, restore, resize, ssh-config...
```

Warstwa `base/` ma własny stan, więc skasowanie maszyn nie kasuje obrazów.
`testboxes/` i `infra/` czytają z niej identyfikatory obrazów przez
`terraform_remote_state`, a maszyny tworzą wspólnym modułem. **Kolejność ma
znaczenie:** najpierw `base/`, potem maszyny; przy kasowaniu odwrotnie.

## Maszyny

| Maszyna | Warstwa | Profil cloud-init | System | vCPU | Pamięć | Dysk | Sieć | Działa |
|---|---|---|---|---:|---:|---:|---|---|
| `deb11`, `deb12`, `deb13` | testboxes | base | Debian 11, 12, 13 | 2 | 2 GiB | 10 GiB | lab | tak |
| `ubu2204`, `ubu2404`, `ubu2604` | testboxes | base | Ubuntu 22.04, 24.04, 26.04 | 2 | 2 GiB | 10 GiB | lab | tak |
| `kdev` | infra | desktop | Ubuntu 24.04 + KDE | 4 | 8 GiB | 20 GiB | default | tak |
| `pbs` | infra | pbs | Debian 12 + Proxmox Backup Server | 2 | 4 GiB | 10 + 4×50 GiB | default | tak |
| `awx` | infra | k3s | Ubuntu 24.04 + k3s | 4 | 8 GiB | 40 GiB | default | tak, z autostartem |
| `docker` | infra | docker | Debian 13 + Docker | 2 | 4 GiB | 20 GiB | default | tak |
| `mon` | infra | docker | Debian 13 + Docker | 4 | 6 GiB | 30 GiB | default | nie |

Profil `base` zakłada konto z kluczem SSH, agenta QEMU i Pythona - cel dla
Ansible. Dyski danych `pbs` zostają puste: magazyn kopii zakłada się ręcznie,
żeby Terraform nigdy go nie skasował. Maszynę dodajesz wierszem w mapie `vms`
w `testboxes/variables.tf` albo `infra/variables.tf`.

## Wymagania hosta

Pakiety (Debian 13). Bez pakietów zalecanych doszłoby ich ponad 360, w tym
GTK, GStreamer i Mesa, zbędne na serwerze:

```bash
sudo apt-get install --no-install-recommends \
  qemu-system-x86 qemu-utils ovmf qemu-system-modules-spice \
  libvirt-daemon-system libvirt-clients dnsmasq-base nftables \
  genisoimage xsltproc make jq curl
sudo usermod -aG libvirt,kvm "$USER"    # potem ponowne logowanie
```

Dwa z nich Terraform zgłasza dopiero błędem przy `apply`:

- `genisoimage` daje `mkisofs`, którym provider buduje dysk z konfiguracją
  startową. Bez niego: `exec: "mkisofs": executable file not found in $PATH`.
- `xsltproc` jest wołany dla bloku `xml { xslt = ... }`, który mają wszystkie
  maszyny. Bez niego: `exec: "xsltproc": executable file not found in $PATH`.

Sieć `default` i pulę na dyski maszyn trzeba mieć przed pierwszym `apply` -
Debian po instalacji libvirt zostawia sieć nieaktywną i nie tworzy żadnej puli:

```bash
sudo virsh net-autostart default && sudo virsh net-start default
sudo virsh pool-define-as images dir --target /var/lib/libvirt/images
sudo virsh pool-build images && sudo virsh pool-start images && sudo virsh pool-autostart images
```

Terraform z [repozytorium HashiCorp](https://developer.hashicorp.com/terraform/install)
albo [OpenTofu](https://opentofu.org/docs/intro/install/) (`make ... TF=tofu`).
Kod przechodzi `validate` w obu.

## Krok po kroku

### 1. Obrazy bazowe w formacie RAW

Provider 0.8.3 przy `disk { file = ... }` wpisuje do definicji maszyny
`<driver type='raw'>` niezależnie od faktycznego formatu pliku. Oficjalne
obrazy chmurowe są w formacie qcow2, więc firmware czyta nagłówek qcow2 jako
tablicę partycji i maszyna nie startuje (UEFI, od angielskiego *Unified
Extensible Firmware Interface*, kończy w powłoce; SeaBIOS zgłasza „not a
bootable disk”). Rozwiązaniem są obrazy RAW - provider dziedziczy format ze
źródła:

```bash
mkdir -p ~/lab-golden
for d in 11:bullseye 12:bookworm 13:trixie; do
  v=${d%%:*}; c=${d##*:}
  scripts/cloud-image-to-raw.sh \
    https://cloud.debian.org/images/cloud/$c/latest/debian-$v-genericcloud-amd64.qcow2 \
    ~/lab-golden/debian-$v.raw
done
for v in 22.04 24.04 26.04; do
  scripts/cloud-image-to-raw.sh \
    https://cloud-images.ubuntu.com/releases/$v/release/ubuntu-$v-server-cloudimg-amd64.img \
    ~/lab-golden/ubuntu-${v/./}.raw
done
```

Katalog musi być trwały (nie `/tmp`): warstwa bazowa czyta te pliki przy
każdym odtwarzaniu obrazu.

### 2. Lokalne ustawienia

```bash
cp base/local-images.auto.tfvars.example   base/local-images.auto.tfvars      # podmień /home/UZYTKOWNIK
cp testboxes/testboxes.auto.tfvars.example testboxes/testboxes.auto.tfvars
cp infra/infra.auto.tfvars.example         infra/infra.auto.tfvars
```

Pliki `*.auto.tfvars` ładują się automatycznie i **nadpisują całe mapy**
z `variables.tf` - sam wpis w `variables.tf` nie wystarczy, jeśli lokalny plik
podaje własną mapę. `disk_strategy = "copy"` robi z każdej maszyny samodzielną
kopię obrazu: nakładka copy-on-write (`cow`) na hostach z AppArmor nie startuje,
bo `virt-aa-helper` nie dopisuje pliku bazowego do profilu maszyny.

### 3. Konto, klucz i hasło

Domyślnie konto `admin` z kluczem `~/.ssh/id_ed25519.pub`. **Zmień hasło**:
szablony cloud-init włączają logowanie hasłem (`ssh_pwauth: true`), a domyślna
wartość `user_password` to `changeme`. Maszyny stoją w sieciach NAT hosta, ale
to ustawienie dla labu, nie dla niczego wystawionego na świat:

```bash
cp terraform.tfvars.example testboxes/terraform.tfvars   # i tak samo dla infra/
# ustaw: user_password = "..."; ewentualnie username i ssh_public_key_path
```

### 4. Budowa

```bash
make base                          # pula, obrazy, sieć lab (init + apply)
make init  DIR=testboxes && make apply DIR=testboxes
make init  DIR=infra     && make apply DIR=infra
virsh -c qemu:///system list --all
```

`make apply DIR=testboxes ONLY='["testdeb"]'` buduje tylko wybraną grupę.
Uwaga: to, czego nie ma w filtrze, a jest w stanie, zostanie zaplanowane do
usunięcia - czytaj linię `Plan: X to add, Y to change, Z to destroy`.

### 5. Logowanie po nazwie maszyny

```bash
make ssh-config                    # zapisuje ~/.ssh/config-lab z adresami z agenta QEMU
ssh deb13
```

Jeśli maszyny działają na innym hoście niż ten, na którym generujesz config
(a oba hosty mają te same podsieci NAT), dodaj przeskok:

```bash
make ssh-config URI=qemu+ssh://lab-host/system JUMP=lab-host
```

## Operacje dnia drugiego

```bash
make restore DIR=testboxes VM=deb13        # jedna maszyna od zera (dysk, seed, domena)
make restore DIR=testboxes GROUP=testdeb   # cała grupa
make resize  VM=deb13 GB=30                # powiększ dysk (tylko w górę) + restart
make up VM=mon / make down VM=mon          # włącz, wyłącz łagodnie
make console VM=deb13                      # konsola szeregowa
make destroy DIR=infra; make destroy DIR=testboxes; make destroy DIR=base
```

## Poprawki XML domen (XSLT)

Provider 0.8.3 nie ma argumentów do ustawienia zegarów ani do usunięcia
domyślnej grafiki, więc każda maszyna dostaje arkusz XSLT (od angielskiego
*XSL Transformations*) z `modules/vm-group/domain.xsl.tftpl`:

- dyski `*.qcow2` (dyski danych `pbs`) dostają właściwy typ sterownika,
- zegary jak w `virt-install`: bez emulowanego HPET (od angielskiego *High
  Precision Event Timer*). Emulacja HPET budziła proces QEMU 250 razy na
  sekundę i kosztowała 3,3-5,8% rdzenia hosta na każdą bezczynną maszynę,
- maszyny bez pulpitu tracą grafikę SPICE i kartę `cirrus`, które provider
  dodaje domyślnie - kolejne ok. 1,7% rdzenia na maszynę.

Na naszym hoście dziesięć maszyn zeszło dzięki temu z 5,3-5,9 W do 4,2 W, a razem
z preferencją energetyczną procesora `balance_power` do ok. 3,3 W.
Pomiary: [Laptop jako host KVM](https://linuxlab.pl/zuzycie-energii-host-kvm-laptop.html).

**Każda zmiana treści szablonu XSLT, także komentarza, odtwarza domeny** - do
`xslt` trafia wyrenderowany tekst. Dyski zostają, ale maszyny wyłącz łagodnie
przed `apply`.

## Znane pułapki (sprawdzone)

- **Zmiana w miejscu włącza wyłączoną maszynę.** Provider zapisuje dysk w stanie
  jako `volume_id`, a kod podaje `file`, więc każdy plan pokazuje zmianę w
  miejscu dla wszystkich maszyn. Taka zmiana uruchamia domenę z
  `running = false`: po `apply` w `infra/` wyłącz `mon` (`make down VM=mon`).
- **Debian 11 jest po końcu wsparcia.** Konfiguracja startowa `deb11` kończy
  się błędem, bo repozytorium bezpieczeństwa wskazuje już nieistniejący plik
  `qemu-guest-agent` (404). Maszyna działa, ale adres bierzesz z DHCP (od
  angielskiego *Dynamic Host Configuration Protocol*).
- **Debiany: agent QEMU startuje dopiero po restarcie maszyny.** Do tego
  czasu `virsh domifaddr --source agent` nic nie zwraca; `make ssh-config`
  sięga wtedy po dzierżawę DHCP.
- **Po restarcie hosta wstaje tylko `awx`.** Skrypt `libvirt-guests` w Debianie
  ma `ON_BOOT=ignore` i `ON_SHUTDOWN=shutdown`, więc startują tylko maszyny
  z `autostart = true`. Resztę włącz `make up`, nie `apply` (patrz pierwsza
  pułapka).
- **`kdev`: serwer X pada w pętli.** Z pakietem `xserver-xorg-video-qxl` 0.1.6
  X kończy się błędem segmentacji w `xf86ProbeOutputModes` kilka razy na minutę,
  a SDDM go restartuje - usługa jest „aktywna”, pulpit nie działa. Obejście,
  sprawdzone ręcznie w gościu: `sudo apt-get remove xserver-xorg-video-qxl`
  (X przechodzi na sterownik `modesetting`). Profil `desktop` jeszcze tego nie
  robi.
- **`awx`: `kubectl` z k3s** domyślnie czyta `/etc/rancher/k3s/k3s.yaml`
  (tylko root). Użyj `kubectl --kubeconfig ~/.kube/config`.
- **Pamięć:** maszyny z tabeli mają zadeklarowane razem 36 GiB, ale fizycznie
  zajmują tylko to, czego użyją. U nas po czterech godzinach było to ok. 9 GiB.

## Licencja

[Apache License 2.0](../LICENSE), jak całe repozytorium.
