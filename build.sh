#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build_work="${CLICKPOD_BUILD_DIR:-${TMPDIR:-/tmp}/clickpod-build}"
mkdir -p "ClickPod.app/Contents/MacOS" "ClickPod.app/Contents/Resources" "$build_work/module-cache"
xcrun swiftc Source/ClickPod.swift -o ClickPod.app/Contents/MacOS/ClickPod -target arm64-apple-macosx14.0 -framework Cocoa -framework SwiftUI -framework SceneKit -lsqlite3 -module-cache-path "$build_work/module-cache" -O
cp Assets/ipod-mesh.json ClickPod.app/Contents/Resources/
if [ ! -f Assets/ClickPod.icns ]; then
  xcrun swift -module-cache-path "$build_work/module-cache" Source/make_icon.swift "$build_work/ClickPod.iconset" Assets/ClickPod.icns
fi
cp Assets/ClickPod.icns ClickPod.app/Contents/Resources/
cat > ClickPod.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>ClickPod</string><key>CFBundleIdentifier</key><string>studio.astra.clickpod</string><key>CFBundleName</key><string>ClickPod</string><key>CFBundleDisplayName</key><string>ClickPod</string><key>CFBundleIconFile</key><string>ClickPod</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>1.0</string><key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - ClickPod.app
