#!/usr/bin/env bash
# PikoMacV kaldirma scripti
# Kullanim: curl -fsSL https://raw.githubusercontent.com/atalay111-ux/PikoMacV/main/uninstall.sh | bash
set -euo pipefail

APP_NAME="PikoMacV"
PROCESS_NAME="PikoMacV"
KEYCHAIN_SERVICE="com.pikomacv.secrets"

log() { printf '==> %s\n' "$*"; }
warn() { printf 'UYARI: %s\n' "$*" >&2; }
die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

if [ "$(uname -s)" != "Darwin" ]; then
  die "Bu kaldirma scripti yalnizca macOS icin."
fi

# 1. Uygulamayi kapat
log "Uygulama kapatiliyor (calisiyorsa)..."
pkill -x "$PROCESS_NAME" || true
sleep 1

# 2. Uygulama kopyalarini kaldir
for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
  if [ -e "$app" ]; then
    if rm -rf "$app" 2>/dev/null; then
      log "Silindi: $app"
    else
      warn "Silinemedi: $app (yetki sorunu olabilir)"
    fi
  fi
done

# 3. Kullanici verileri: yalnizca terminal varsa sor, varsayilan Hayir
DELETE_DATA=0
HAS_TTY=0
if (: </dev/tty) 2>/dev/null; then
  HAS_TTY=1
fi

if [ "$HAS_TTY" -eq 1 ]; then
  printf 'Kullanici verileri (ayarlar, onbellek ve anahtarlik kayitlari) da silinsin mi? [e/H]: '
  answer=""
  read -r answer </dev/tty || answer=""
  case "$answer" in
    e|E|evet|Evet|EVET|y|Y|yes|Yes) DELETE_DATA=1 ;;
    *) DELETE_DATA=0 ;;
  esac
else
  log "Etkilesimli terminal yok; kullanici verileri korunuyor."
fi

if [ "$DELETE_DATA" -eq 1 ]; then
  log "Kullanici verileri siliniyor..."
  rm -rf "$HOME/Library/Application Support/$APP_NAME"
  rm -rf "$HOME/Library/Caches/$APP_NAME"

  count=0
  while security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; do
    count=$((count + 1))
  done
  log "Anahtarlik kaydi silindi: $count"
else
  log "Kullanici verileri korundu."
fi

cat <<EOF

PikoMacV kaldirildi.

Not: Erisilebilirlik izni kaydi otomatik silinmez. Istersen elle kaldirabilirsin:
  Sistem Ayarlari > Gizlilik ve Guvenlik > Erisilebilirlik
EOF
