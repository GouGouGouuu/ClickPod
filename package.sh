#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version="1.0.0"
[ -d ClickPod.app ] || bash build.sh
codesign --verify --deep --strict ClickPod.app
mkdir -p dist
ditto -c -k --norsrc --keepParent ClickPod.app "dist/ClickPod-v${version}-macOS-arm64.zip"
(cd dist && shasum -a 256 "ClickPod-v${version}-macOS-arm64.zip" > SHA256SUMS.txt)
printf 'Release package: dist/ClickPod-v%s-macOS-arm64.zip\n' "$version"
