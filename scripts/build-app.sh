#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
export CLANG_MODULE_CACHE_PATH="$root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/module-cache"
swift build --disable-sandbox -c release --cache-path "$root/.build/cache"
bin_dir="$(swift build --disable-sandbox -c release --cache-path "$root/.build/cache" --show-bin-path)"
app="$root/dist/Tapr.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Unlink first so a running Tapr keeps its own executable pages.
rm -f "$app/Contents/MacOS/Tapr"
cp "$bin_dir/Tapr" "$app/Contents/MacOS/Tapr"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Tapr</string>
<key>CFBundleDisplayName</key><string>Tapr</string>
<key>CFBundleIdentifier</key><string>local.tapr.poc</string>
<key>CFBundleExecutable</key><string>Tapr</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.5</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
