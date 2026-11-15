#!/usr/bin/env bash
# PikoMacV uygulamasini derler, .app paketini olusturur, ad-hoc imzalar ve zip'ler.
#
# Kullanim:
#   scripts/build-app.sh          # arm64 + x86_64 (evrensel) release derlemesi, dist/PikoMacV.zip
#   scripts/build-app.sh --fast   # yalnizca bu Mac'in mimarisi, debug; zip olusturulmaz
set -euo pipefail

FAST=0
for arg in "$@"; do
    case "$arg" in
        --fast) FAST=1 ;;
        -h|--help)
            echo "Kullanim: $0 [--fast]"
            exit 0
            ;;
        *)
            echo "Bilinmeyen secenek: $arg" >&2
            echo "Kullanim: $0 [--fast]" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="PikoMacV"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_SRC="$ROOT/packaging/Info.plist"
ICON_SRC="$ROOT/packaging/AppIcon.icns"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"

if [[ "$FAST" -eq 1 ]]; then
    echo "==> Hizli mod: yalnizca bu Mac'in mimarisi, debug derlemesi"
    swift build --product PikoMacV --scratch-path .build-fast
    BINARY="$ROOT/.build-fast/debug/$APP_NAME"
else
    echo "==> arm64 release derlemesi"
    swift build -c release --product PikoMacV --triple arm64-apple-macosx14.0 --scratch-path .build-arm64
    ARM_BINARY="$ROOT/.build-arm64/release/$APP_NAME"

    X86_BINARY="$ROOT/.build-x86_64/release/$APP_NAME"
    echo "==> x86_64 release derlemesi"
    if swift build -c release --product PikoMacV --triple x86_64-apple-macosx14.0 --scratch-path .build-x86_64; then
        X86_OK=1
    else
        X86_OK=0
        echo "UYARI: x86_64 derlemesi basarisiz oldu. Uygulama yalnizca arm64 (Apple Silicon) icin olusturulacak." >&2
    fi

    mkdir -p "$DIST_DIR"
    if [[ "$X86_OK" -eq 1 && -f "$ARM_BINARY" && -f "$X86_BINARY" ]]; then
        echo "==> lipo ile evrensel ikili olusturuluyor"
        UNIVERSAL_BINARY="$DIST_DIR/$APP_NAME.universal"
        lipo -create -output "$UNIVERSAL_BINARY" "$ARM_BINARY" "$X86_BINARY"
        BINARY="$UNIVERSAL_BINARY"
    else
        BINARY="$ARM_BINARY"
    fi
fi

if [[ ! -f "$BINARY" ]]; then
    echo "HATA: ikili bulunamadi: $BINARY" >&2
    exit 1
fi

echo "==> $APP_DIR olusturuluyor"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_SRC" "$CONTENTS_DIR/Info.plist"

if [[ -f "$ICON_SRC" ]]; then
    echo "==> Uygulama simgesi ekleniyor"
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist"
fi

echo "==> Ad-hoc imzalama"
# Kalıcı imza: anahtar zincirinde "MacV Code Signing" kimliği varsa onunla imzala.
# Böylece macOS uygulamayı derlemeler arasında aynı uygulama olarak tanır ve
# Erişilebilirlik izni güncellemelerde korunur. Kimlik yoksa geçici (ad-hoc) imzaya düşer.
SIGN_ID="MacV Code Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN_ID\""; then
  codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
  echo "Uyari: \"$SIGN_ID\" kimligi bulunamadi; gecici imza kullaniliyor (izinler her derlemede sifirlanir)."
  codesign --force --deep --sign - "$APP_DIR"
fi

if [[ "$FAST" -eq 1 ]]; then
    echo "==> Zip atlandi (--fast)"
    echo "Uygulama : $APP_DIR"
    echo "Ikili    : $BINARY"
    exit 0
fi

echo "==> Zip olusturuluyor"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Tamamlandi"
echo "Uygulama : $APP_DIR"
echo "Zip      : $ZIP_PATH"
