#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
APP="$HOME/Applications/Quickshot.app"
AGENT="$HOME/Library/LaunchAgents/local.quickshot.plist"
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Pictures/Quickshot" "$ROOT/state"
if [[ ! -f "$ROOT/state/screencapture-before.plist" ]]; then
  defaults export com.apple.screencapture "$ROOT/state/screencapture-before.plist"
  chmod 600 "$ROOT/state/screencapture-before.plist"
fi
"$ROOT/build/Quickshot.app/Contents/MacOS/Quickshot" --quit-running
launchctl bootout "gui/$(id -u)/local.quickshot" 2>/dev/null || true
if [[ -d "$APP" ]]; then
  ditto "$APP" "$ROOT/state/Quickshot-before.app"
fi
ditto "$ROOT/build/Quickshot.app" "$APP"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Quickshot"
defaults write com.apple.screencapture target -string file
defaults write com.apple.screencapture target-screenshot -string file
defaults write com.apple.screencapture type -string png
defaults write com.apple.screencapture show-thumbnail -bool false
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.quickshot</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>-a</string><string>$APP</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
<key>StandardErrorPath</key><string>$ROOT/state/quickshot.log</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
print 'Installed Quickshot and enabled screenshot handoff.'
