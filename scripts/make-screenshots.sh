#!/usr/bin/env bash
# Belge ekran görüntülerini docs/screenshots/ altına üretir.
#
# Gerçek veriye ve panoya dokunmaz: demo örneği PIKOMACV_DATA_DIR ile geçici bir klasörde, ayrı Anahtar Zinciri
# servis adıyla (com.pikomacv.secrets.demo) ve pano izleme kapalı (PIKOMACV_NO_MONITOR=1) çalışır.
# Ekran Kaydı izni gerekmez: uygulama kendi penceresini yakalar; yalnızca arka plan sentetiktir.
#
# Kullanim: scripts/make-screenshots.sh [--no-build]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/docs/screenshots"
APP="$ROOT/dist/PikoMacV.app/Contents/MacOS/PikoMacV"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pikomacv-shots.XXXXXX")"
HOOK="$WORK/pikomacv-hook"
DATA="$WORK/data"
APP_PID=""

cleanup() {
    [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true
    pkill -f "PikoMacV.app/Contents/MacOS/PikoMacV" 2>/dev/null || true
    # Demo gizli sabitlerini sil (her çağrı bir öğe siler).
    for _ in $(seq 1 20); do
        security delete-generic-password -s com.pikomacv.secrets.demo >/dev/null 2>&1 || break
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

if [[ "${1:-}" != "--no-build" ]]; then
    echo "==> Derleme (--fast)"
    "$SCRIPT_DIR/build-app.sh" --fast >"$WORK/build.log" 2>&1 || { cat "$WORK/build.log"; exit 1; }
fi
echo "==> Yardımcı derleniyor"
swiftc -O "$SCRIPT_DIR/pikomacv-hook.swift" -o "$HOOK"

# Çalışan başka bir kopya olmasın (gerçek uygulama dahil: tek kopya kuralı).
pkill -f "PikoMacV.app/Contents/MacOS/PikoMacV" 2>/dev/null || true
sleep 1
mkdir -p "$OUT" "$DATA"

echo "==> Demo örneği başlatılıyor"
PIKOMACV_DATA_DIR="$DATA" PIKOMACV_NO_MONITOR=1 PIKOMACV_FAKE_ACCESSIBILITY=1 "$APP" --debug-hooks --seed-demo >"$WORK/app.log" 2>&1 &
APP_PID=$!
for _ in $(seq 1 40); do [[ -s "$DATA/history.json" ]] && break; sleep 0.25; done
sleep 2
kill -0 "$APP_PID" 2>/dev/null || { echo "Uygulama başlamadı"; cat "$WORK/app.log"; exit 1; }

hook() { "$HOOK" "$@"; }

# snap <kanca> <dosya>: kancayı gönderir, dosyanın yazılmasını bekler.
snap() {
    local kind="$1" arg="$2" file="$3"
    rm -f "$file"
    hook "$kind" "$arg"
    for _ in $(seq 1 40); do
        [[ -s "$file" ]] && { sleep 0.2; echo "   $(basename "$file")"; return 0; }
        sleep 0.15
    done
    echo "UYARI: $(basename "$file") üretilemedi" >&2
    return 1
}

# panel <dosya> <general|pinned> <sekme> <hedef "bundle|ad"> <satır>
panel() {
    local file="$1" mode="$2" tab="$3" target="$4" row="${5:-0}"
    hook close; sleep 0.3
    hook target "$target"
    hook show "$mode"; sleep 0.9
    hook tab "$tab"; hook select "$row"; sleep 0.6
    snap snap "$file" "$file" || { sleep 1; snap snap "$file" "$file"; }
    hook close; sleep 0.3
}

# Isınma turu: ilk açılışta SwiftUI/pencere sunucusu hazır olmayabiliyor.
hook appearance light
hook show general; sleep 1.5; hook close; sleep 0.5
panel "$OUT/panel-gecmis.png"    general Uygun    "com.microsoft.Word|Word"   0
panel "$OUT/panel-finder.png"    general Uygun    "com.apple.finder|Finder"   0
panel "$OUT/panel-sabitler.png"  pinned  Sabitler "com.microsoft.Word|Word"   0
hook appearance dark
panel "$OUT/panel-koyu.png"      general Uygun    "com.microsoft.Word|Word"   0
hook appearance light
hook target ""

echo "==> Pencereler"
hook settings kısayollar; sleep 1.2
snap snapwindow "settings|$OUT/ayarlar-kisayollar.png" "$OUT/ayarlar-kisayollar.png"
hook settings depolama; sleep 1.2
snap snapwindow "settings|$OUT/ayarlar-depolama.png" "$OUT/ayarlar-depolama.png"
hook onboarding 2; sleep 1.2
snap snapwindow "onboarding|$OUT/kurulum-kisayollar.png" "$OUT/kurulum-kisayollar.png"

hook quit
sleep 1
echo "==> Bitti: $OUT"
