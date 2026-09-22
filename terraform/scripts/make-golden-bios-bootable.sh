#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  make-golden-bios-bootable.sh
#  Zrób z oficjalnego cloud image golden image BOOTOWALNY PRZEZ BIOS (SeaBIOS).
#  Turn an official Debian/Ubuntu cloud image into a BIOS-bootable golden image.
# ----------------------------------------------------------------------------
#  PO CO / WHY:
#    Na jednym z naszych hostów (qemu 10 + OVMF/EDK2 2.70) firmware NIE bootował obrazów
#    cloud: SeaBIOS pisze "could not read the boot disk" / "not a bootable disk"
#    (obrazy genericcloud/generic/cloudimg nie mają kodu boot w MBR - są UEFI),
#    a OVMF nie enumeruje GPT na dysku virtio (ściana firmware). Działają tylko
#    dyski z KODEM BOOT BIOS (jak maszyna zainstalowana ręcznie z instalatora).
#
#    UWAGA: właściwą przyczyną okazał się format dysku (provider wpisuje
#    type='raw', a obrazy były qcow2) - patrz README. Zalecana ścieżka to
#    obraz RAW + UEFI; ten skrypt zostaje jako alternatywa dla BIOS.
#
#    Ten skrypt bierze oficjalny cloud image (z cloud-init!) i DOINSTALOWUJE
#    GRUB dla BIOS (i386-pc) do partycji bios_grub + MBR. Efekt: obraz wciąż ma
#    cloud-init, ale bootuje na SeaBIOS - omija problem OVMF.
#
#  WYMAGA ROOTA na hoście libvirt (qemu-nbd, mount, chroot, grub-install).
#  Guest w chroot potrzebuje sieci (apt) - montujemy resolv.conf.
#
#  UŻYCIE / USAGE:
#    sudo lab/scripts/make-golden-bios-bootable.sh \
#         https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
#         /var/lib/libvirt/images/golden/debian-12-bios.qcow2
#
#    (1. arg = URL albo lokalna ścieżka cloud image; 2. arg = plik wynikowy.)
#
#  POTEM w base/: wskaż ten plik jako źródło obrazu, np. terraform.tfvars:
#      distros = { "debian-12" = { pretty = "Debian 12 BIOS"
#                  latest_url = "/var/lib/libvirt/images/golden/debian-12-bios.qcow2" } }
#      enabled_distros = ["debian-12"]
#    i stawiaj VM w trybie copy + BIOS:
#      cd testboxes && terraform apply -var='disk_strategy=copy'
#    (disk_strategy=copy bo na tym hoście AppArmor nie whitelistuje backing CoW.)
# ============================================================================
set -euo pipefail

SRC="${1:?Podaj URL lub ścieżkę cloud image (1. arg)}"
DST="${2:?Podaj ścieżkę pliku wynikowego (2. arg)}"
NBD="${NBD:-/dev/nbd7}"

[[ $EUID -eq 0 ]] || { echo "Uruchom jako root (sudo)."; exit 1; }
command -v qemu-nbd  >/dev/null || { echo "Brak qemu-utils (qemu-nbd)."; exit 1; }
command -v grub-install >/dev/null || true # grub-install jest W GOŚCIU (chroot)

work="$(mktemp -d)"
cleanup() {
  set +e
  mountpoint -q "$work/mnt/dev"  && umount -R "$work/mnt/dev"
  mountpoint -q "$work/mnt/proc" && umount "$work/mnt/proc"
  mountpoint -q "$work/mnt/sys"  && umount "$work/mnt/sys"
  mountpoint -q "$work/mnt"      && umount -R "$work/mnt"
  qemu-nbd --disconnect "$NBD" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

echo ">> 1) Pobieram/kopiuję źródło -> $DST"
mkdir -p "$(dirname "$DST")"
if [[ "$SRC" =~ ^https?:// ]]; then
  curl -fL --retry 3 -o "$DST" "$SRC"
else
  cp --reflink=auto "$SRC" "$DST"
fi
# Ubuntu rozprowadza .img (to qcow2) - normalizujemy do qcow2 nieskompresowanego.
qemu-img convert -O qcow2 "$DST" "$DST.norm" && mv "$DST.norm" "$DST"

echo ">> 2) Podłączam przez qemu-nbd ($NBD)"
modprobe nbd max_part=16
qemu-nbd --connect="$NBD" "$DST"
sleep 1
partprobe "$NBD" || true; sleep 1

echo ">> 3) Wykrywam partycję root (największy ext4)"
ROOT=""
for p in "${NBD}"p*; do
  [[ -b "$p" ]] || continue
  fs="$(blkid -o value -s TYPE "$p" 2>/dev/null || true)"
  [[ "$fs" == ext4 ]] && ROOT="$p" && break
done
[[ -n "$ROOT" ]] || { echo "Nie znalazłem partycji root (ext4)."; exit 1; }
echo "   root = $ROOT"

echo ">> 4) Montuję + chroot, instaluję grub-pc i piszę GRUB BIOS do MBR ($NBD)"
mkdir -p "$work/mnt"
mount "$ROOT" "$work/mnt"
# ESP (jeśli jest) pod /boot/efi - nieobowiązkowe dla BIOS, ale nie szkodzi.
mount --bind /dev  "$work/mnt/dev"
mount --bind /proc "$work/mnt/proc"
mount --bind /sys  "$work/mnt/sys"

# DZIAŁAJĄCY DNS w chroot: NIE kopiuj ślepo /etc/resolv.conf (na hoście to często
# stub systemd-resolved 127.0.0.53, który w chroot NIE działa => "Temporary
# failure resolving"). Użyj realnego upstreamu hosta, a w ostateczności publicznego.
rm -f "$work/mnt/etc/resolv.conf"
if [[ -s /run/systemd/resolve/resolv.conf ]]; then
  cp /run/systemd/resolve/resolv.conf "$work/mnt/etc/resolv.conf"
elif grep -q '^nameserver' /etc/resolv.conf 2>/dev/null && ! grep -q '127.0.0.53' /etc/resolv.conf; then
  cp -L /etc/resolv.conf "$work/mnt/etc/resolv.conf"
else
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' >"$work/mnt/etc/resolv.conf"
fi

chroot "$work/mnt" /bin/bash -eux <<CHROOT
export DEBIAN_FRONTEND=noninteractive
apt-get update
# grub-pc-bin = pliki platformy i386-pc (BIOS) + grub-install. Cloud images mają
# zwykle tylko grub-efi; instalujemy grub-pc-bin (NIE meta 'grub-pc', które na
# obrazie cloud bywa "no candidate" i odpala debconf o wybór dysku).
apt-get install -y grub-pc-bin grub2-common
# boot.img do MBR + core.img do partycji bios_grub całego dysku.
grub-install --target=i386-pc --recheck "$NBD"
update-grub
CHROOT

echo ">> 5) Odłączam nbd i konwertuję do RAW"
# KLUCZOWE: provider dmacvicar z `disk { file = ... }` deklaruje dysk jako
# <driver type='raw'>. Jeśli plik jest qcow2 => qemu czyta nagłówek qcow2 jako
# MBR/GPT i firmware NIE bootuje ("not a bootable disk"). Dlatego golden MUSI być
# RAW, żeby format się zgadzał. (To była PRAWDZIWA przyczyna nieudanych bootów.)
umount -R "$work/mnt/dev" 2>/dev/null || true
umount "$work/mnt/proc" "$work/mnt/sys" 2>/dev/null || true
umount -R "$work/mnt" 2>/dev/null || true
qemu-nbd --disconnect "$NBD" 2>/dev/null || true
sleep 1
qemu-img convert -O raw "$DST" "$DST.raw" && mv "$DST.raw" "$DST"

echo ">> 6) Gotowe. $DST jest BIOS-bootowalny + RAW (i nadal ma cloud-init)."
echo "   format: $(qemu-img info "$DST" 2>/dev/null | awk -F': ' '/file format/{print $2}')"
echo "   W base/ ustaw latest_url = \"$DST\"; w roocie VM użyj disk_strategy=copy."
