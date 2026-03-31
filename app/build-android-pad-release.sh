#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PACK_ASSETS_DIR="android/samples_pack/src/main/assets"
PACK_SAMPLES_DIR="$PACK_ASSETS_DIR/samples"
SOURCE_SAMPLES_DIR="samples"
PUBSPEC_FILE="pubspec.yaml"
PUBSPEC_BACKUP=".pubspec.yaml.pad.backup"

if [[ ! -d "$SOURCE_SAMPLES_DIR" ]]; then
  echo "Missing source samples directory: $SOURCE_SAMPLES_DIR" >&2
  exit 1
fi

cleanup() {
  if [[ -f "$PUBSPEC_BACKUP" ]]; then
    mv "$PUBSPEC_BACKUP" "$PUBSPEC_FILE"
    flutter pub get >/dev/null
  fi
}
trap cleanup EXIT

echo "Syncing built-in samples into Android asset pack..."
mkdir -p "$PACK_ASSETS_DIR"
rm -rf "$PACK_SAMPLES_DIR"
rsync -a --delete "$SOURCE_SAMPLES_DIR/" "$PACK_SAMPLES_DIR/"
python3 - <<'PY'
from pathlib import Path
for ds in Path("android/samples_pack/src/main/assets/samples").rglob(".DS_Store"):
    ds.unlink(missing_ok=True)
PY

echo "Preparing temporary Android release pubspec (without bundled samples/)..."
cp "$PUBSPEC_FILE" "$PUBSPEC_BACKUP"
python3 - <<'PY'
from pathlib import Path

path = Path("pubspec.yaml")
lines = path.read_text(encoding="utf-8").splitlines(True)
result = []
for line in lines:
    stripped = line.strip()
    # Keep everything except flutter asset declarations that bundle samples/.
    if stripped.startswith("- samples/"):
        continue
    result.append(line)
path.write_text("".join(result), encoding="utf-8")
PY

echo "Running flutter pub get for temporary pubspec..."
flutter pub get

# Strip flutter_build cache so kernel depfiles match this pubspec (no bundled samples/).
# Reusing incremental artifacts after swapping assets causes empty/invalid kernel_snapshot_program.d warnings.
rm -rf .dart_tool/flutter_build

echo "Building Android AAB with PAD (flavor=prod, release)..."
flutter build appbundle --flavor prod --release

echo "Build complete:"
echo "  build/app/outputs/bundle/prodRelease/app-prod-release.aab"
