#!/bin/bash
# =====================================================================
#  Dell Vostro 3520 - EFI otomatik düzeltme (ses + kablolu ethernet)
#  Çalıştırma:   bash ~/Downloads/efi_otomatik_duzelt.sh
#  Şifre sorarsa Mac şifreni yaz (EFI'yi bağlamak için gerekiyor).
#
#  Yaptıkları:
#   1. OpenCore'un açıldığı EFI bölümünü bulur ve bağlar
#   2. config.plist'in YEDEĞİNİ alır (EFI'ye ve Masaüstüne)
#   3. AppleALC.kext ve RealtekRTL8111.kext'in son sürümünü indirir, Kexts'e koyar
#   4. config.plist'e ekler:
#        - Kernel > Add: AppleALC, RealtekRTL8111 (yoksa)
#        - ACPI > Patch: HDAS -> HDEF (yoksa)
#        - DeviceProperties: ses layout-id = 15
#   5. WhateverXe varsa WhateverGreen'i ve VoodooHDA'yı devre dışı bırakır
#  Bir şey bozulursa: OpenCore menüsünde açılmazsa USB'den boot et ve
#  EFI/OC/config.plist.yedek_* dosyasını config.plist olarak geri koy.
# =====================================================================
set -u
LAYOUT_B64="DwAAAA=="   # 15. Başka ID denemek için: 3=AwAAAA== 11=CwAAAA== 13=DQAAAA== 16=EAAAAA==
HDA_PATH="PciRoot(0x0)/Pci(0x1F,0x3)"

kirmizi() { printf "\033[31m%s\033[0m\n" "$1"; }
yesil()   { printf "\033[32m%s\033[0m\n" "$1"; }
sari()    { printf "\033[33m%s\033[0m\n" "$1"; }
dur()     { kirmizi "HATA: $1"; exit 1; }

# ---------- 1. EFI bölümünü bul ----------
# Önce bulunduğun klasöre bakar (cd ile EFI'ye girdiysen onu kullanır)
OC=""
for c in "$PWD/EFI/OC" "$PWD/OC" "$PWD"; do
  if [ -f "$c/config.plist" ] && [ -d "$c/Kexts" ]; then OC="$c"; break; fi
done
if [ -n "$OC" ]; then
  yesil "Bulundugun klasor kullaniliyor: $OC"
else
echo "EFI bolumu araniyor..."
BOOTPATH="$(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:boot-path 2>/dev/null | cut -f2-)"
UUID="$(echo "$BOOTPATH" | sed -nE 's/.*GPT,([0-9A-Fa-f-]{36}).*/\1/p')"
EFIDEV=""
if [ -n "$UUID" ]; then
  EFIDEV="$(diskutil info "$UUID" 2>/dev/null | awk -F': *' '/Device Identifier/ {print $2; exit}')"
fi
if [ -z "$EFIDEV" ]; then
  sari "OpenCore'un acildigi bolum otomatik bulunamadi. EFI bolumleri:"
  diskutil list | grep -i "EFI"
  read -r -p "Kullanilacak EFI bolumunu yaz (ornek disk0s1): " EFIDEV
fi
[ -n "$EFIDEV" ] || dur "EFI bolumu secilmedi."
echo "EFI bolumu: $EFIDEV"

sudo diskutil mount "$EFIDEV" >/dev/null || dur "EFI baglanamadi."
MNT="$(diskutil info "$EFIDEV" | awk -F': *' '/Mount Point/ {print $2; exit}')"
OC="$MNT/EFI/OC"
fi
CFG="$OC/config.plist"
[ -f "$CFG" ] || dur "$CFG bulunamadi."
yesil "Bulundu: $CFG"

# ---------- 2. Yedek ----------
TS="$(date +%Y%m%d_%H%M%S)"
sudo cp "$CFG" "$CFG.yedek_$TS" || dur "Yedek alinamadi."
cp "$CFG" "$HOME/Desktop/config.plist.yedek_$TS"
yesil "Yedek alindi: config.plist.yedek_$TS (EFI/OC ve Masaustu)"

WORK="$(mktemp -d)"
cp "$CFG" "$WORK/config.plist"
P="$WORK/config.plist"
plutil -lint "$P" >/dev/null || dur "Mevcut config.plist bozuk, once onu duzelt."

# ---------- Yardımcılar ----------
kext_sayisi() { plutil -extract Kernel.Add raw "$P" 2>/dev/null || echo 0; }
kext_index() {   # $1 = BundlePath, ornek AppleALC.kext ; index yazar, yoksa bos
  local n i b; n="$(kext_sayisi)"
  for ((i=0;i<n;i++)); do
    b="$(plutil -extract "Kernel.Add.$i.BundlePath" raw "$P" 2>/dev/null)"
    [ "$b" = "$1" ] && { echo "$i"; return; }
  done
}
kext_ekle() {    # $1 = kext adi (AppleALC)
  local name="$1"
  if [ -n "$(kext_index "$name.kext")" ]; then
    plutil -replace "Kernel.Add.$(kext_index "$name.kext").Enabled" -bool YES "$P"
    echo "  $name zaten config'te (etkinlestirildi)."; return
  fi
  plutil -insert Kernel.Add -xml "<dict>
    <key>Arch</key><string>Any</string>
    <key>BundlePath</key><string>$name.kext</string>
    <key>Comment</key><string>$name</string>
    <key>Enabled</key><true/>
    <key>ExecutablePath</key><string>Contents/MacOS/$name</string>
    <key>MaxKernel</key><string></string>
    <key>MinKernel</key><string></string>
    <key>PlistPath</key><string>Contents/Info.plist</string>
  </dict>" -append "$P" && echo "  $name config'e eklendi."
}
kext_indir() {   # $1 = github repo, $2 = kext adi
  local repo="$1" name="$2" url dir
  if [ -d "$OC/Kexts/$name.kext" ]; then echo "  $name.kext zaten Kexts klasorunde."; return 0; fi
  echo "  $name indiriliyor..."
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' | grep -vi debug | head -1 | sed 's/.*"\(http[^"]*\)"/\1/')"
  [ -n "$url" ] || { kirmizi "  $name indirme linki bulunamadi (internet var mi?)."; return 1; }
  dir="$WORK/$name"; mkdir -p "$dir"
  curl -fsSL "$url" -o "$dir/k.zip" && unzip -q -o "$dir/k.zip" -d "$dir" || { kirmizi "  $name indirilemedi."; return 1; }
  local k; k="$(find "$dir" -type d -name "$name.kext" -not -path "*/__MACOSX/*" | grep -vi debug | head -1)"
  [ -n "$k" ] || { kirmizi "  Arsivde $name.kext yok."; return 1; }
  sudo cp -R "$k" "$OC/Kexts/" && echo "  $name.kext Kexts klasorune kopyalandi."
}

# ---------- 3. Kontroller ----------
echo; echo "Mevcut kextler kontrol ediliyor..."
[ -n "$(kext_index Lilu.kext)" ] || dur "Lilu.kext config'te yok! Once Lilu ekle."
HAS_WEX="$(kext_index WhateverXe.kext)"

# ---------- 4. Kext indir + ekle ----------
echo; echo "Kextler:"
kext_indir "acidanthera/AppleALC" "AppleALC" && kext_ekle "AppleALC"
kext_indir "Mieze/RTL8111_driver_for_OS_X" "RealtekRTL8111" && kext_ekle "RealtekRTL8111"

# Çakışanları kapat
for bad in VoodooHDA.kext; do
  i="$(kext_index "$bad")"; [ -n "$i" ] && plutil -replace "Kernel.Add.$i.Enabled" -bool NO "$P" && sari "  $bad devre disi birakildi (AppleALC ile cakisir)."
done
if [ -n "$HAS_WEX" ]; then
  i="$(kext_index WhateverGreen.kext)"; [ -n "$i" ] && plutil -replace "Kernel.Add.$i.Enabled" -bool NO "$P" && sari "  WhateverGreen devre disi birakildi (WhateverXe ile birlikte kullanilmaz)."
fi

# ---------- 5. ACPI rename HDAS -> HDEF ----------
echo; echo "ACPI:"
if ! plutil -extract ACPI.Patch xml1 -o - "$P" 2>/dev/null | grep -q "SERBUw=="; then
  plutil -insert ACPI.Patch -xml "<dict>
    <key>Base</key><string></string>
    <key>BaseSkip</key><integer>0</integer>
    <key>Comment</key><string>HDAS to HDEF</string>
    <key>Count</key><integer>0</integer>
    <key>Enabled</key><true/>
    <key>Find</key><data>SERBUw==</data>
    <key>Limit</key><integer>0</integer>
    <key>Mask</key><data></data>
    <key>OemTableId</key><data></data>
    <key>Replace</key><data>SERFRg==</data>
    <key>ReplaceMask</key><data></data>
    <key>Skip</key><integer>0</integer>
    <key>TableLength</key><integer>0</integer>
    <key>TableSignature</key><data></data>
  </dict>" -append "$P" && echo "  HDAS -> HDEF eklendi."
else
  echo "  HDAS -> HDEF zaten var."
fi

# ---------- 6. DeviceProperties layout-id ----------
echo; echo "DeviceProperties:"
if plutil -extract "DeviceProperties.Add.$HDA_PATH" xml1 -o - "$P" >/dev/null 2>&1; then
  plutil -replace "DeviceProperties.Add.$HDA_PATH.layout-id" -data "$LAYOUT_B64" "$P"
else
  plutil -insert "DeviceProperties.Add.$HDA_PATH" -xml "<dict><key>layout-id</key><data>$LAYOUT_B64</data></dict>" "$P"
fi
echo "  Ses layout-id ayarlandi."

# alcid boot-arg varsa uyar
BA="$(plutil -extract "NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args" raw "$P" 2>/dev/null)"
echo "$BA" | grep -q "alcid=" && sari "  Not: boot-args icinde alcid= var, layout-id'yi o ezer."

# ---------- 7. Kontrol ve kaydet ----------
plutil -lint "$P" >/dev/null || dur "Yeni config.plist gecersiz cikti, hicbir sey degistirilmedi."
echo
read -r -p "Degisiklikler EFI'ye yazilsin mi? (e/h): " CEVAP
if [ "$CEVAP" = "e" ] || [ "$CEVAP" = "E" ]; then
  sudo cp "$P" "$CFG" && yesil "config.plist guncellendi. Simdi yeniden baslat."
else
  sari "Iptal edildi, EFI'de hicbir sey degismedi (indirilen kextler Kexts klasorunde kaldi)."
fi
rm -rf "$WORK"
