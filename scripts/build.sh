#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/Dave Save Importer.app"
mkdir -p "$app/Contents/MacOS"
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun swiftc Sources/main.swift -o "$app/Contents/MacOS/DaveSaveImporter" -framework Cocoa -O
codesign --force --deep --sign - "$app"
echo "Built: $app"
