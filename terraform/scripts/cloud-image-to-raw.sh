#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 SysGroup Sp. z o.o.
# ============================================================================
#  cloud-image-to-raw.sh - pobierz cloud image i zapisz jako RAW (BEZ roota)
#  Download a cloud image and save it as RAW (NO root needed).
# ----------------------------------------------------------------------------
#  PO CO / WHY:
#    Provider dmacvicar z `disk { file = ... }` deklaruje dysk jako
#    <driver type='raw'>, IGNORUJĄC prawdziwy format. Jeśli golden jest qcow2,
#    qemu/firmware czyta nagłówek qcow2 jako MBR/GPT => VM nie bootuje
#    ("not a bootable disk" / UEFI shell). Dlatego golden MUSI być RAW.
#    Provider dziedziczy format ze ŹRÓDŁA, więc wystarczy raw source.
#
#    Z RAW + firmware=uefi (domyślne) OVMF czyta GPT/ESP ORYGINALNEGO cloud image
#    i bootuje BOOTX64.EFI - bez grub-pc i bez roota.
#
#  UŻYCIE / USAGE:
#    lab/scripts/cloud-image-to-raw.sh \
#      https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 \
#      ~/lab-golden/debian-13.raw
#
#    (zapisz w TRWAŁYM katalogu - nie /tmp, bo base/ czyta ten plik przy każdym
#     `terraform apply` warstwy base. Plik 0644 jest czytelny dla libvirtd/root.)
#
#  POTEM w base/local-images.auto.tfvars:
#    distros = { "debian-13" = { pretty="Debian 13", latest_url="~/.../debian-13.raw" } }
#    enabled_distros = ["debian-13"]
#  i w roocie VM: disk_strategy="copy" (firmware=uefi jest domyślne).
# ============================================================================
set -euo pipefail

SRC="${1:?Podaj URL lub ścieżkę cloud image (1. arg)}"
DST="${2:?Podaj ścieżkę wynikową .raw/.img (2. arg)}"

command -v qemu-img >/dev/null || { echo "Brak qemu-img (qemu-utils)."; exit 1; }
mkdir -p "$(dirname "$DST")"

tmp="$(mktemp --suffix=.img)"
trap 'rm -f "$tmp"' EXIT

if [[ "$SRC" =~ ^https?:// ]]; then
  echo ">> pobieram $SRC"
  curl -fL --retry 3 -o "$tmp" "$SRC"
else
  cp --reflink=auto "$SRC" "$tmp"
fi

echo ">> konwersja do RAW -> $DST"
qemu-img convert -O raw "$tmp" "$DST"
chmod 644 "$DST"
echo ">> OK: $DST (format: $(qemu-img info "$DST" 2>/dev/null | awk -F': ' '/file format/{print $2}'))"
