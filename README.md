# Keyboard Layout Switcher

Switch keyboard layouts from the Omarchy bar or with Ctrl+Space, and type any
layout's characters from a clickable keyboard viewer. Every connected keyboard
switches together.

![Keyboard layout menu with English and Spanish](preview.png)

## Requirements

- Omarchy Quattro
- Your layouts in `kb_layout` in `~/.config/hypr/input.lua`, for example
  `kb_layout = "us,es"` for English (US) and Spanish

The plugin uses `hyprctl`, `xkbcli`, `python3` and `wtype`, which Omarchy
installs by default. It has no other dependencies.

## Install

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

## Use

Click the bar icon and choose a layout. A check mark shows the active layout.
Below the layouts:

- **Show Emojis** opens Omarchy's Emojis picker.
- **Show Keyboard Viewer** opens the [keyboard viewer](#keyboard-viewer).
- **Show Input Source Name** shows the full layout name in the bar.
- **Open Keyboard Settings…** opens `~/.config/hypr/input.lua` in your editor.

Use the arrow keys or `j`/`k` to move through the menu, Enter to select, and
Esc to close.

![Keyboard icon and input source name while the menu is open](bar-source-name.png)

## Settings

Open the bar editor to change these:

- **Bar Appearance**: a filled badge, an outlined badge, or plain text.
- **Show Input Source Name in Bar**: the full layout name beside the badge.
- **Show … in Menu**: hide any of the menu items above.
- **Keyboard Viewer Shape**: ANSI, ISO, ABNT or JIS, if Auto picks the wrong
  one for your keyboard.

## Optional shortcuts

Add these bindings to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

Tap Ctrl+Space to return to the last layout. Keep Ctrl held and press Space to
cycle through layouts. Ctrl+Alt+Space moves to the next layout. Change the
bindings if they conflict with your apps.

![Layout switcher with Spanish selected](shortcut-switcher.png)

Scripts can use the same commands:

```bash
omarchy-shell jesusarchive.keyboard-layout-switcher set es      # by layout, code (ES) or index
omarchy-shell jesusarchive.keyboard-layout-switcher current     # prints the active code, e.g. EN
omarchy-shell jesusarchive.keyboard-layout-switcher list        # all layouts as JSON
omarchy-shell jesusarchive.keyboard-layout-switcher toggle      # open or close the menu
omarchy-shell jesusarchive.keyboard-layout-switcher viewer      # open or close the keyboard viewer
```

## Keyboard viewer

Choose **Show Keyboard Viewer** from the menu. It shows the active layout and
types into the app that has keyboard focus.

![Keyboard viewer with the English (US) layout](keyboard-viewer.png)

- Click Shift, Ctrl, Alt, Super, or AltGr once for the next key. Double-click
  to lock it; click again to turn it off. Caps Lock toggles letter case.
- Click an outlined accent key, then a letter, to compose it. Hold a letter to
  choose an accented form.
- Drag the header to move the viewer, use the bottom-right corner to resize it,
  and click × to close it.

The viewer does not highlight physical key presses.

## Update or remove

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

If you added the shortcuts, remove them from `~/.config/hypr/bindings.lua`.

## License

[MIT](LICENSE)
