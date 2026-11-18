#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
APP="$ROOT/build/Quickshot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HOME/.cache/quickshot-swift"
cp "$ROOT/Assets/Quickshot.icns" "$APP/Contents/Resources/Quickshot.icns"
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$HOME/.cache/quickshot-swift" -framework AppKit -framework CoreServices -framework CoreText -framework ImageIO -framework UniformTypeIdentifiers "$ROOT/Sources/Quickshot.swift" -o "$APP/Contents/MacOS/Quickshot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Quickshot</string>
<key>CFBundleIdentifier</key><string>local.quickshot</string>
<key>CFBundleName</key><string>Quickshot</string>
<key>CFBundleIconFile</key><string>Quickshot.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.image</string></array>
</dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print -r -- "$APP"
