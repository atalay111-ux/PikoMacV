#!/usr/bin/env bash
# Surum yayinlama scripti. Yalnizca insan tarafindan elle calistirilir.
# Kullanim: scripts/release.sh [--dry-run] vMAJOR.MINOR.PATCH
set -euo pipefail

usage() {
  echo "Kullanim: scripts/release.sh [--dry-run] vMAJOR.MINOR.PATCH" >&2
  echo "Ornek:    scripts/release.sh v1.0.0" >&2
  exit 1
}

DRY_RUN=0
TAG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    -*) echo "Bilinmeyen secenek: $arg" >&2; usage ;;
    *)
      if [ -n "$TAG" ]; then usage; fi
      TAG="$arg"
      ;;
  esac
done
if [ -z "$TAG" ]; then usage; fi

if [[ ! "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Hata: gecersiz surum etiketi '$TAG'. Beklenen bicim: vMAJOR.MINOR.PATCH" >&2
  exit 1
fi
VERSION="${TAG#v}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PLIST="$REPO_ROOT/packaging/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "Hata: $PLIST bulunamadi" >&2
  exit 1
fi

echo "==> Surum ayarlaniyor: $VERSION"
if ! /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"
fi

echo "==> Uygulama derleniyor ve paketleniyor..."
bash "$REPO_ROOT/scripts/build-app.sh"

ZIP="$REPO_ROOT/dist/PikoMacV.zip"
if [ ! -f "$ZIP" ]; then
  echo "Hata: $ZIP olusturulamadi" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "==> Arsiv: $ZIP"
echo "==> SHA-256: $SHA256"

GH_CMD=(gh release create "$TAG" "$ZIP" --title "PikoMacV $TAG" --generate-notes)

if [ "$DRY_RUN" -eq 1 ]; then
  echo "==> [dry-run] Calistirilacak komut (calistirilmadi):"
  printf '  %q' "${GH_CMD[@]}"
  echo
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Hata: gh (GitHub CLI) bulunamadi" >&2
  exit 1
fi

echo "==> GitHub release olusturuluyor: $TAG"
"${GH_CMD[@]}"
echo "==> Tamamlandi: $TAG"
