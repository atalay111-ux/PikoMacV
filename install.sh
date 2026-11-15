#!/usr/bin/env bash
# PikoMacV kurulum scripti
# Kullanim: curl -fsSL https://raw.githubusercontent.com/atalay111-ux/PikoMacV/main/install.sh | bash
set -euo pipefail

APP_NAME="PikoMacV"
PROCESS_NAME="PikoMacV"
DEFAULT_ZIP_URL="https://github.com/atalay111-ux/PikoMacV/releases/latest/download/PikoMacV.zip"
ZIP_URL="${PIKOMACV_ZIP_URL:-$DEFAULT_ZIP_URL}"
UNINSTALL_URL="https://raw.githubusercontent.com/atalay111-ux/PikoMacV/main/uninstall.sh"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'UYARI: %s\n' "$*" >&2; }
die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

# 1. Platform ve macOS surum kontrolu
if [ "$(uname -s)" != "Darwin" ]; then
  die "Bu kurulum yalnizca macOS icin. Algilanan sistem: $(uname -s)"
fi

OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
if ! [[ "$OS_MAJOR" =~ ^[0-9]+$ ]] || [ "$OS_MAJOR" -lt 14 ]; then
  die "PikoMacV icin macOS 14 (Sonoma) veya uzeri gerekli. Mevcut surum: $OS_VERSION"
fi
log "macOS $OS_VERSION algilandi."

# 2. Gecici dizin ve temizlik
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# 3. Indirme
ZIP_PATH="$TMP_DIR/PikoMacV.zip"
log "PikoMacV indiriliyor..."
if ! curl -fL --retry 3 -o "$ZIP_PATH" "$ZIP_URL"; then
  die "Indirme basarisiz: $ZIP_URL"
fi

# 4. Calisan uygulamayi kapat
log "Calisan uygulama varsa kapatiliyor..."
pkill -x "$PROCESS_NAME" || true
sleep 1

# 5. Arsivi ac ve dogrula
EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"
log "Arsiv aciliyor..."
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

APP_SRC="$EXTRACT_DIR/$APP_NAME.app"
if [ ! -f "$APP_SRC/Contents/MacOS/$APP_NAME" ]; then
  die "Arsivde $APP_NAME.app/Contents/MacOS/$APP_NAME bulunamadi. Arsiv bozuk olabilir."
fi

log "Kod imzasi dogrulaniyor..."
if ! codesign --verify --deep "$APP_SRC"; then
  die "Kod imzasi dogrulanamadi. Kurulum guvenlik nedeniyle iptal edildi."
fi

# 6. Kurulum konumunu sec (sudo kullanilmaz)
DEST_DIR="/Applications"
if [ ! -w "$DEST_DIR" ]; then
  DEST_DIR="$HOME/Applications"
  mkdir -p "$DEST_DIR"
  warn "/Applications yazilabilir degil, $DEST_DIR kullanilacak."
fi
APP_DEST="$DEST_DIR/$APP_NAME.app"

# 7. Eski surumu kaldir ve yeni surumu kopyala
if [ -e "$APP_DEST" ]; then
  log "Eski surum kaldiriliyor..."
  rm -rf "$APP_DEST"
fi
log "Uygulama $APP_DEST konumuna kuruluyor..."
ditto "$APP_SRC" "$APP_DEST"

# 8. Karantina niteligini kaldir (hata olursa devam et)
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true

# 9. Uygulamayi baslat
log "PikoMacV baslatiliyor..."
if ! open "$APP_DEST"; then
  warn "Uygulama otomatik baslatilamadi. Finder'dan elle acabilirsiniz."
fi

cat <<EOF

Kurulum tamamlandi.

Sonraki adimlar:
  1. Uygulama sorarsa Sistem Ayarlari > Gizlilik ve Guvenlik > Erisilebilirlik
     bolumunden PikoMacV'ye izin verin. Bu izin otomatik yapistirma ve fare
     tusu kisayollari icin gereklidir.
  2. Ilk acilista kurulum sihirbazi kisayollarinizi secmenize yardimci olur.
  3. Verileriniz bu Mac uzerinde saklanir.

Kaldirmak icin:
  curl -fsSL $UNINSTALL_URL | bash
EOF
