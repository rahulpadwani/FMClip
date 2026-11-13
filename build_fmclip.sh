#!/bin/bash
# Builds FMClip.app from FMClip.swift and installs it in /Applications.
set -e
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed. Run:  xcode-select --install"
  echo "Then run this script again."
  exit 1
fi

BUILD="$(mktemp -d)/FMClip.app"
mkdir -p "$BUILD/Contents/MacOS"

echo "Compiling…"
swiftc -O -parse-as-library FMClip.swift -o "$BUILD/Contents/MacOS/FMClip"

# App icon (built from FMClip_icon.png if it's next to this script)
if [ -f FMClip_icon.png ]; then
  echo "Adding icon…"
  mkdir -p "$BUILD/Contents/Resources"
  ICONSET="$(mktemp -d)/FMClip.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s FMClip_icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) FMClip_icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD/Contents/Resources/FMClip.icns"
fi

cat > "$BUILD/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FMClip</string>
  <key>CFBundleDisplayName</key><string>FMClip</string>
  <key>CFBundleIdentifier</key><string>com.williamssignal.fmclip</string>
  <key>CFBundleExecutable</key><string>FMClip</string>
  <key>CFBundleIconFile</key><string>FMClip</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$BUILD" >/dev/null 2>&1 || true

osascript -e 'quit app "FMClip"' >/dev/null 2>&1 || true
rm -rf /Applications/FMClip.app
cp -R "$BUILD" /Applications/FMClip.app
touch /Applications/FMClip.app
echo "Installed /Applications/FMClip.app"
sleep 1
open /Applications/FMClip.app || echo "Open FMClip from Applications."
