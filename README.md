# Quickshot

A tiny native Mac screenshot annotator. No toolbar, onboarding, network access, or third-party dependencies.

- Drag for an arrow. Shift-drag for a box.
- Click and type to add text. Click existing text to edit it.
- Return adds a line; Cmd–Return finishes editing; Escape cancels the edit.
- Close the window to copy a full-resolution PNG and return to your previous app.
- Cmd–Z / Shift–Cmd–Z undo and redo. Delete removes the last annotation when you’re not typing.
- Cmd–C copies the image when you’re not editing text.

Quickshot stays ready in the background and starts at login. It uses macOS’s existing **save a selected area to a file** shortcut—normally Cmd–Shift–4, or your custom shortcut. It does not register or change keyboard shortcuts. Clipboard-only screenshot shortcuts bypass Quickshot.

## Build and install

Requires Apple silicon, macOS 14 or later, and Apple’s Command Line Tools (`xcode-select --install`).

```sh
./build.sh
./scripts/install-launchagent.sh
```

The installer places the app in `~/Applications`, saves screenshots in `~/Pictures/Quickshot`, and disables the floating screenshot thumbnail so images open immediately. Original screenshots are preserved. Previous screenshot settings are backed up locally in `state/`.

Stop Quickshot and restore those settings:

```sh
./scripts/uninstall.sh
```

## Verify

```sh
./scripts/test.sh
```

Tests exercise drag gestures, text entry/editing/deletion/cancellation, undo/redo, Retina export, and copying text that is still being edited when the window closes. They use an offscreen AppKit window in a normal macOS login session, preserve the clipboard, and save generated fixtures in `build/test-results/`.
