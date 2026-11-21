#!/bin/bash
# =====================================================================
#  Vostro 3520 - dahili ekran (eDP) denemesi için WhateverXe ayarları
#  Kullanım:  sudo diskutil mount disk0s1 ; cd /Volumes/EFI ; bash ~/Downloads/ekran_duzelt.sh
#  Ekler:
#    - IGPU DeviceProperties: framebuffer-patch-enable + framebuffer-stolenmem
#      (WhateverXe: DVMT 60MB'ta sabitse ve -igfxdvmt kullanılıyorsa GEREKLİ)
#    - SSDT-PNLF.aml (dahili ekran parlaklığı / arka ışık)
#  Önce yedek alır. Yazmadan önce sorar.
# =====================================================================
set -u
kirmizi() { printf "\033[31m%s\033[0m\n" "$1"; }
yesil()   { printf "\033[32m%s\033[0m\n" "$1"; }
dur()     { kirmizi "HATA: $1"; exit 1; }

OC=""
for c in "$PWD/EFI/OC" "$PWD/OC" "$PWD"; do
  [ -f "$c/config.plist" ] && [ -d "$c/ACPI" ] && { OC="$c"; break; }
done
[ -n "$OC" ] || dur "EFI klasorunde degilsin. Once: sudo diskutil mount disk0s1 ; cd /Volumes/EFI"
CFG="$OC/config.plist"
yesil "Kullanilan: $CFG"

TS="$(date +%Y%m%d_%H%M%S)"
sudo cp "$CFG" "$CFG.yedek_$TS" && cp "$CFG" "$HOME/Desktop/config.plist.yedek_$TS" || dur "Yedek alinamadi."
yesil "Yedek alindi: config.plist.yedek_$TS"

WORK="$(mktemp -d)"; P="$WORK/config.plist"; cp "$CFG" "$P"
plutil -lint "$P" >/dev/null || dur "config.plist bozuk."

# --- 1. IGPU framebuffer ozellikleri ---
IG="PciRoot(0x0)/Pci(0x2,0x0)"
if ! plutil -extract "DeviceProperties.Add.$IG" xml1 -o - "$P" >/dev/null 2>&1; then
  plutil -insert "DeviceProperties.Add.$IG" -xml "<dict></dict>" "$P"
fi
plutil -replace "DeviceProperties.Add.$IG.framebuffer-patch-enable" -data "AQAAAA==" "$P"   # 01000000
plutil -replace "DeviceProperties.Add.$IG.framebuffer-stolenmem"   -data "AADAAw==" "$P"   # 0000C003
echo "  IGPU: framebuffer-patch-enable + framebuffer-stolenmem eklendi."

# --- 2. SSDT-PNLF ---
if [ ! -f "$OC/ACPI/SSDT-PNLF.aml" ]; then
  echo "  SSDT-PNLF indiriliyor..."
  curl -fsSL "https://github.com/dortania/Getting-Started-With-ACPI/raw/master/extra-files/compiled/SSDT-PNLF.aml" \
    -o "$WORK/SSDT-PNLF.aml" && sudo cp "$WORK/SSDT-PNLF.aml" "$OC/ACPI/" && echo "  SSDT-PNLF.aml ACPI klasorune kopyalandi." \
    || kirmizi "  SSDT-PNLF indirilemedi, elle ekle."
fi
if ! plutil -extract ACPI.Add xml1 -o - "$P" 2>/dev/null | grep -q "SSDT-PNLF.aml"; then
  plutil -insert ACPI.Add -xml "<dict>
    <key>Comment</key><string>SSDT-PNLF</string>
    <key>Enabled</key><true/>
    <key>Path</key><string>SSDT-PNLF.aml</string>
  </dict>" -append "$P" && echo "  SSDT-PNLF config'e eklendi."
fi

plutil -lint "$P" >/dev/null || dur "Yeni config gecersiz, hicbir sey degismedi."
read -r -p "EFI'ye yazilsin mi? (e/h): " C
if [ "$C" = "e" ] || [ "$C" = "E" ]; then
  sudo cp "$P" "$CFG" && yesil "Tamam. Yeniden baslat. HDMI kablosu TAKILI DEGILKEN dene."
else
  echo "Iptal edildi."
fi
rm -rf "$WORK"
