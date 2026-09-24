# Keyboard Layout Switcher

Switch keyboard layouts from the Omarchy bar or a shortcut, and type from a
clickable on-screen keyboard. Every connected keyboard switches together.

![Keyboard layout menu](preview.png)

## Requirements

- Omarchy Quattro
- Two or more layouts in `kb_layout` in `~/.config/hypr/input.lua`

The plugin uses `hyprctl`, `xkbcli`, `python3` and `wtype`. Omarchy installs
all four by default.

## Install

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

## Use

Click the bar icon and choose a layout. A check mark shows the active layout.
The menu also has these items:

- **Show Emojis** opens Omarchy's Emojis picker.
- **Show Keyboard Viewer** opens the [keyboard viewer](#keyboard-viewer).
- **Show Input Source Name** adds the full layout name next to the bar icon.
- **Open Keyboard Settings…** opens `~/.config/hypr/input.lua` in your editor.

Use the arrow keys or `j`/`k` to move through the menu, Enter to select, and
Esc to close.

![Bar icon and layout name while the menu is open](bar-source-name.png)

## Settings

Change these in the bar editor.

| Setting | Key | Default | Effect |
| --- | --- | --- | --- |
| Bar Appearance | `barAppearance` | `icon` | `icon` is a filled icon, `bordered` an outlined one, `text` plain text |
| Show Input Source Name in Bar | `showSourceName` | `false` | Shows the full layout name next to the bar icon |
| Show Emojis in Menu | `showEmojiAndSymbols` | `true` | Shows the **Show Emojis** item |
| Show Keyboard Viewer in Menu | `showKeyboardViewer` | `true` | Shows the **Show Keyboard Viewer** item |
| Show Input Source Name in Menu | `showSourceNameMenuItem` | `true` | Shows the **Show Input Source Name** item |
| Show Keyboard Settings in Menu | `showKeyboardSettings` | `true` | Shows the **Open Keyboard Settings…** item |
| Keyboard Viewer Shape | `keyboardViewerGeometry` | `auto` | Key arrangement in the viewer: `auto`, `ansi`, `iso`, `abnt` or `jis` |

You can also set them from a terminal. Pass `--json` for `true` and `false`,
or the value is saved as text and ignored:

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher barAppearance bordered
omarchy bar set jesusarchive.keyboard-layout-switcher showEmojiAndSymbols false --json
```

## Shortcuts

Add these bindings to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

Tap Ctrl+Space to return to the last layout. Keep Ctrl held and press Space to
cycle through layouts. Ctrl+Alt+Space moves to the next layout. Change the keys
if they conflict with your apps.

![Layout switcher on screen](shortcut-switcher.png)

Scripts can call these commands too:

```bash
omarchy-shell jesusarchive.keyboard-layout-switcher set <layout>   # by layout name, code or index
omarchy-shell jesusarchive.keyboard-layout-switcher current        # prints the active layout code
omarchy-shell jesusarchive.keyboard-layout-switcher list           # prints all layouts as JSON
omarchy-shell jesusarchive.keyboard-layout-switcher toggle         # opens or closes the menu
omarchy-shell jesusarchive.keyboard-layout-switcher viewer         # opens or closes the keyboard viewer
```

## Keyboard viewer

Choose **Show Keyboard Viewer** from the menu. The viewer shows the active
layout, and each click types into the app that has keyboard focus.

![Keyboard viewer](keyboard-viewer.png)

- Click Shift, Ctrl, Alt, Super or AltGr to apply it to the next key.
  Double-click to lock it, and click again to turn it off. Caps Lock toggles
  letter case.
- Click an outlined accent key, then a letter, to type the accented letter.
  Hold a letter to pick from its accented forms.
- Drag the header to move the viewer. Drag the bottom-right corner to resize
  it. Click × to close it.

The viewer does not highlight keys you press on your physical keyboard. If its
key layout does not match your keyboard, change **Keyboard Viewer Shape** in
the bar editor.

## Update or remove

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

If you added the shortcuts, remove them from `~/.config/hypr/bindings.lua`.

## License

[MIT](LICENSE)
