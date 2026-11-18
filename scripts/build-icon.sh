#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
ICONSET="$ROOT/build/Quickshot.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Assets/Quickshot.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT/Assets/Quickshot.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Assets/Quickshot.icns"
