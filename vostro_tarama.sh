#!/bin/bash
# =====================================================================
#  Dell Vostro 3520 Hackintosh - Donanım Tarama Scripti
#  Çalıştırma:  Terminal'i aç ve şunu yaz:
#      bash ~/Downloads/vostro_tarama.sh
#  Sonuç Masaüstüne "vostro_tarama_TARIH.txt" olarak kaydedilir.
#  Bu dosyayı bana geri gönder.
#  Script hiçbir şeyi DEĞİŞTİRMEZ, sadece okur.
# =====================================================================

OUT="$HOME/Desktop/vostro_tarama_$(date +%Y%m%d_%H%M%S).txt"
OZET=""

ozet() { OZET="${OZET}$1"$'\n'; }
bolum() { echo; echo "=================================================="; echo "== $1"; echo "=================================================="; }

# PCI cihazlarını "vendor:device class isim" olarak listeler
pci_listesi() {
  ioreg -r -d 1 -c IOPCIDevice -l 2>/dev/null | awk '
    function le4(h) { return substr(h,3,2) substr(h,1,2) }
    function flush() { if (name != "") printf "%s:%s  class=%s  %s\n", vid, did, cls, name }
    /\+-o / { flush(); name=$2; vid="????"; did="????"; cls="????" }
    /"vendor-id" = </ { v=$0; sub(/.*</,"",v); sub(/>.*/,"",v); vid=le4(v) }
    /"device-id" = </ { d=$0; sub(/.*</,"",d); sub(/>.*/,"",d); did=le4(d) }
    /"class-code" = </ { c=$0; sub(/.*</,"",c); sub(/>.*/,"",c); cls=substr(c,5,2) substr(c,3,2) }
    END { flush() }'
}

echo "Tarama başladı, 1-2 dakika sürebilir..."

{
  echo "VOSTRO 3520 HACKINTOSH TARAMA RAPORU"
  echo "Tarih: $(date)"

  bolum "SISTEM"
  sw_vers
  echo "Kernel: $(uname -r)"
  echo "SMBIOS (model): $(sysctl -n hw.model)"
  echo "CPU: $(sysctl -n machdep.cpu.brand_string)"
  echo "RAM: $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
  echo "OpenCore surumu: $(nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version 2>/dev/null | awk '{print $2}')"
  echo "boot-args: $(nvram boot-args 2>/dev/null | cut -f2-)"
  echo "SIP: $(csrutil status 2>/dev/null)"

  bolum "PCI CIHAZLARI (vendor:device)"
  PCI="$(pci_listesi)"
  echo "$PCI"

  bolum "YUKLU KEXTLER (ucuncu parti)"
  if command -v kmutil >/dev/null 2>&1; then
    KEXTS="$(kmutil showloaded --list-only 2>/dev/null | grep -v com.apple)"
  else
    KEXTS="$(kextstat 2>/dev/null | grep -v com.apple)"
  fi
  echo "$KEXTS"

  bolum "SES - HDEF / Codec"
  ioreg -rxn HDEF 2>/dev/null | grep -E "class IOPCIDevice|layout-id|alc-layout-id|AppleHDAController|class-code|device-id|vendor-id" | head -20
  echo "--- Codec ---"
  ioreg -rxc IOHDACodecDevice 2>/dev/null | grep -E "IOHDACodecVendorID|IOHDACodecRevisionID|IOHDACodecAddress" | head -20
  echo "--- AppleHDA nesneleri ---"
  ioreg -l 2>/dev/null | grep -E "class AppleHDA" | head -10
  echo "--- Ses cihazlari ---"
  system_profiler SPAudioDataType 2>/dev/null

  bolum "GRAFIK"
  system_profiler SPDisplaysDataType 2>/dev/null
  echo "--- IGPU ozellikleri ---"
  ioreg -rxn IGPU 2>/dev/null | grep -E "device-id|AAPL,ig-platform-id|framebuffer|model|class IOPCIDevice" | head -20
  echo "--- Ekran baglantilari (framebuffer) ---"
  ioreg -l 2>/dev/null | grep -iE "AppleIntelFramebuffer|connector-type|display-connect" | head -40

  bolum "AG / WI-FI"
  networksetup -listallhardwareports 2>/dev/null
  echo "--- Arayuzler ---"
  ifconfig -l 2>/dev/null
  system_profiler SPAirPortDataType 2>/dev/null | head -40

  bolum "BLUETOOTH"
  system_profiler SPBluetoothDataType 2>/dev/null | head -40

  bolum "USB"
  ( system_profiler SPUSBHostDataType 2>/dev/null || system_profiler SPUSBDataType 2>/dev/null ) | head -120

  bolum "DEPOLAMA"
  diskutil list 2>/dev/null

  bolum "ACILIS LOGU (ses/wifi/bt ile ilgili satirlar)"
  log show --last boot --style compact --predicate 'process == "kernel"' 2>/dev/null \
    | grep -iE "AppleALC|AppleHDA|itlwm|Airport|IntelBluetooth|BlueTool|Lilu|HDEF|ALC" | tail -120

} > "$OUT" 2>&1

# --------------------- OTOMATIK TESHIS ---------------------
PCI="$(pci_listesi)"
if command -v kmutil >/dev/null 2>&1; then
  KEXTS="$(kmutil showloaded --list-only 2>/dev/null)"
else
  KEXTS="$(kextstat 2>/dev/null)"
fi
has_kext() { echo "$KEXTS" | grep -qi "$1"; }

# Wi-Fi karti
if echo "$PCI" | grep -qi "^10ec:c821"; then
  ozet "[WIFI] Realtek RTL8821CE bulundu -> macOS'ta CALISMAZ. Kart degisimi veya USB Wi-Fi gerekir."
elif echo "$PCI" | grep -qiE "^8086:(51f0|51f1|54f0|a0f0|2723|2725|7af0|7a70)"; then
  ozet "[WIFI] Intel Wi-Fi karti bulundu -> AirportItlwm/itlwm ile calisabilir."
  if has_kext "itlwm"; then ozet "       itlwm/AirportItlwm YUKLU."; else ozet "       itlwm/AirportItlwm YUKLU DEGIL -> EFI'ye ekle."; fi
  if has_kext "IntelBluetoothFirmware"; then ozet "[BT]   IntelBluetoothFirmware YUKLU."; else ozet "[BT]   IntelBluetoothFirmware YUKLU DEGIL -> EFI'ye ekle."; fi
  if has_kext "BlueToolFixup"; then ozet "       BlueToolFixup YUKLU."; else ozet "       BlueToolFixup YUKLU DEGIL (Monterey+ icin gerekli)."; fi
else
  W="$(echo "$PCI" | grep -E "class=0280")"
  ozet "[WIFI] Bilinen bir kart taninmadi. Kablosuz sinifindaki cihaz: ${W:-yok (kart gorunmuyor)}"
fi

# Ses
HDA="$(echo "$PCI" | grep -iE "^8086:51c[0-9a-f]")"
if [ -n "$HDA" ]; then
  if echo "$HDA" | grep -q "class=0401"; then
    ozet "[SES]  Ses denetleyicisi SST/DSP modunda (class 0401) -> AppleALC bununla CALISMAZ. BIOS'ta 'Audio DSP'/'SST' kapatilabiliyor mu bak."
  else
    ozet "[SES]  Ses denetleyicisi HDA modunda -> AppleALC ile calisabilir."
  fi
else
  ozet "[SES]  Alder Lake ses denetleyicisi PCI listesinde bulunamadi."
fi
if has_kext "as.vit9696.Lilu"; then ozet "       Lilu YUKLU."; else ozet "       Lilu YUKLU DEGIL!"; fi
if has_kext "AppleALC"; then ozet "       AppleALC YUKLU."; else ozet "       AppleALC YUKLU DEGIL -> EFI'ye ekle."; fi
if has_kext "VoodooHDA"; then ozet "       UYARI: VoodooHDA yuklu, AppleALC ile cakisir. Sil."; fi
if ioreg -l 2>/dev/null | grep -q "class AppleHDAController"; then ozet "       AppleHDAController bagli (iyi isaret)."; else ozet "       AppleHDAController bagli DEGIL."; fi

# Grafik (WhateverXe)
GPUID="$(echo "$PCI" | grep -iE "^8086:46" | head -1)"
ozet "[GPU]  iGPU: ${GPUID:-bulunamadi}"
if has_kext "WhateverXe"; then ozet "       WhateverXe YUKLU."; else ozet "       WhateverXe YUKLU DEGIL!"; fi
if has_kext "WhateverGreen"; then ozet "       UYARI: WhateverGreen de yuklu -> WhateverXe ile BIRLIKTE KULLANILMAZ, sil."; fi
if has_kext "AMFIPass"; then ozet "       AMFIPass YUKLU."; else ozet "       AMFIPass YUKLU DEGIL (WhateverXe icin Mod surumu gerekli)."; fi
if system_profiler SPDisplaysDataType 2>/dev/null | grep -qi "Metal"; then ozet "       Metal destegi gorunuyor (hizlandirma var)."; else ozet "       Metal gorunmuyor -> hizlandirma yok olabilir."; fi
if ioreg -rxc IOHDACodecDevice 2>/dev/null | grep -qi "0x8086"; then ozet "[HDMI] Intel HDMI ses codec'i gorunuyor."; else ozet "[HDMI] Intel HDMI ses codec'i GORUNMUYOR."; fi
if echo "$PCI" | grep -qi "^10de:"; then ozet "       NVIDIA MX550 bulundu -> macOS'ta da calismaz, kapali tutulmali."; fi

{ bolum "OTOMATIK TESHIS"; echo "$OZET"; } >> "$OUT"

echo
echo "================ OZET ================"
echo "$OZET"
echo "Rapor kaydedildi: $OUT"
echo "Bu dosyayi Claude'a gonder."
