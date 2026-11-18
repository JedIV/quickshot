#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
if [[ -x "$HOME/Applications/Quickshot.app/Contents/MacOS/Quickshot" ]]; then
  "$HOME/Applications/Quickshot.app/Contents/MacOS/Quickshot" --quit-running
fi
launchctl bootout "gui/$(id -u)/local.quickshot" 2>/dev/null || true
if [[ -f "$ROOT/state/screencapture-before.plist" ]]; then
  defaults import com.apple.screencapture "$ROOT/state/screencapture-before.plist"
fi
if [[ -f "$HOME/Library/LaunchAgents/local.quickshot.plist" ]]; then
  mv "$HOME/Library/LaunchAgents/local.quickshot.plist" "$ROOT/state/local.quickshot.disabled.plist"
fi
print 'Quickshot stopped; previous macOS screenshot settings restored.'
