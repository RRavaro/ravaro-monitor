#!/bin/bash
# Baut RAVARO Monitor.app ohne Xcode und legt sie nach ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=1.26

# Das Claude-Symbol kommt nur mit, wenn die private Datei daliegt. OEFFENTLICH=1 baut die Fassung mit Roboterkopf.
SYMBOL=""
if [ -f Sources/RavaroMonitor/ClaudeSymbol.swift ] && [ "${OEFFENTLICH:-0}" != "1" ]; then SYMBOL="-Xswiftc -DPRIVATES_SYMBOL"; fi
# RAVARO_BAUORT legt die Zwischendateien woanders ab, falls die Hauptplatte knapp ist.
BAUORT="${RAVARO_BAUORT:-.build}"
swift build -c release $SYMBOL --scratch-path "$BAUORT" 2>&1 | tail -3
BIN="$BAUORT/release/RavaroMonitor"

APP="$HOME/Applications/RAVARO Monitor.app"
pkill -x RavaroMonitor 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fonts" "$HOME/Applications"
cp "$BIN" "$APP/Contents/MacOS/RavaroMonitor"
cp Ressourcen/ravaro-r.png "$APP/Contents/Resources/"
cp Ressourcen/fonts/*.ttf "$APP/Contents/Resources/fonts/"
cp Ressourcen/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RAVARO Monitor</string>
<key>CFBundleDisplayName</key><string>RAVARO Monitor</string>
<key>CFBundleIdentifier</key><string>de.ravaro.monitor</string>
<key>CFBundleExecutable</key><string>RavaroMonitor</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>ATSApplicationFontsPath</key><string>fonts</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" 2>&1 | tail -1
echo "gebaut: $APP"
