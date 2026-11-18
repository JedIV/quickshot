# Quickshot

<img src="Assets/Quickshot.png" width="96" alt="Quickshot target icon">

Fast, native Mac screenshot annotations. No toolbar.

## Install

Apple silicon, macOS 14+, and Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/JedIV/quickshot.git
cd quickshot
./build.sh
./scripts/install-launchagent.sh
```

Starts at login. Screenshots go to `~/Pictures/Quickshot`; the floating thumbnail is disabled for speed. Original images are preserved.

## Use

Capture a region with macOS’s **save-to-file** shortcut (normally ⌘⇧4; custom bindings work too).

- **Drag:** arrow. **Shift-drag:** box.
- **Click and type:** text. Click existing text to edit.
- **⌘Return:** finish typing. **Escape:** cancel the edit.
- **Delete:** remove the last annotation when not typing. **⌘Z:** undo.
- **Close / ⌘W:** copy the annotated PNG at full resolution.

Clipboard-only capture shortcuts bypass Quickshot.

Stop and restore previous screenshot settings: `./scripts/uninstall.sh`

Run tests: `./scripts/test.sh`
