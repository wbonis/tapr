#!/bin/bash
# Renders Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
mkdir -p .build Resources docs
swiftc -O -o .build/make-icon scripts/make-icon.swift
.build/make-icon .build/icon-1024.png
iconset=.build/AppIcon.iconset
rm -rf "$iconset"; mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size .build/icon-1024.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double .build/icon-1024.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
sips -z 256 256 .build/icon-1024.png --out docs/icon.png >/dev/null
printf 'Wrote Resources/AppIcon.icns and docs/icon.png\n'
