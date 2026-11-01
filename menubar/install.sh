#!/bin/bash
# Bygger menyrads-appen och ser till att den startar automatiskt vid inloggning.
# Kör om skriptet efter ändringar i StudietidMenubar.swift. Ta bort autostart med:
#   launchctl bootout gui/$(id -u)/se.studietid.menubar && rm ~/Library/LaunchAgents/se.studietid.menubar.plist
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/studietid-menubar"
LABEL="se.studietid.menubar"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swiftc -swift-version 5 -O -o "$BIN" "$DIR/StudietidMenubar.swift"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x studietid-menubar 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Klart: menyrads-appen körs och startar vid inloggning."
