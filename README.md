# FMClip

<img src="FMClip_icon.png" width="96" align="right" alt="FMClip icon">

A small macOS app that converts the clipboard between **FileMaker objects** and **plain XML text**.

- Copy script steps in FileMaker → get XML text you can paste anywhere (Claude, VS Code, Slack, Notes).
- Copy FileMaker XML from anywhere → paste it straight into FileMaker's Script Workspace.

Two panes, side by side:

| Left: FileMaker | Right: Text (XML) |
|---|---|
| Readable step preview (`Set Variable [ $x ; Value: … ]`, If/Else indented) | Editable `fmxmlsnippet` XML |
| **Copy for FileMaker** (⇧⌘C) | **Copy Text** (⌥⌘C) |

Clipboard contents load automatically when you switch to the app (toggle **Auto-load clipboard** to turn this off).

## Supported objects

Scripts, script steps, custom functions, fields, tables, value lists, layout objects.

## Build & install

Requires macOS 12+ and Apple's Command Line Tools (`xcode-select --install`).

```bash
bash build_fmclip.sh
```

This compiles `FMClip.swift`, adds the icon, installs `/Applications/FMClip.app`, and opens it.

## Usage

**FileMaker → text**
1. Select steps or scripts in Script Workspace, press ⌘C.
2. Switch to FMClip — they load automatically.
3. Click **Copy Text**, then paste anywhere.

**Text → FileMaker**
1. Copy the `fmxmlsnippet` XML.
2. Switch to FMClip — it loads automatically; check the preview on the left.
3. Click **Copy for FileMaker**, then ⌘V in Script Workspace
   (step area for steps, script list for whole scripts).

Fields, table occurrences and scripts that don't exist in the target file paste as `<Field Missing>` / `<Table Missing>` — normal FileMaker behavior.

## Sharing the built app

```bash
ditto -c -k --keepParent /Applications/FMClip.app ~/Desktop/FMClip.zip
```

The app is ad-hoc signed, so on first launch the recipient opens it, then goes to
**System Settings → Privacy & Security → Open Anyway**. A build only runs on the same Mac
architecture it was built on (Apple Silicon vs Intel).

## Files

| File | Purpose |
|---|---|
| `FMClip.swift` | The app (SwiftUI) |
| `build_fmclip.sh` | Builds, adds icon, installs to /Applications |
| `FMClip_icon.png` | 1024×1024 app icon source |
