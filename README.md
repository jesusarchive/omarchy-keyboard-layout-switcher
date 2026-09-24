# Keyboard Layout Switcher

Switch keyboard layouts from the Omarchy bar. The plugin reads
`~/.config/hypr/input.lua`, shows the active layout, and switches all connected
keyboards together. It also provides an optional shortcut switcher and a
clickable keyboard viewer.

![Keyboard layout menu with English and Spanish](preview.png)

## Install

Requires Omarchy Quattro with shell plugins. Omarchy supplies `hyprctl`,
`xkbcli`, `wtype`, Python 3, and libxkbcommon.

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

Omarchy also has a built-in keyboard layout widget. If both appear in the bar,
disable the built-in one with `omarchy plugin disable omarchy.keyboard-layout`.
The plugin starts in the right section of the bar.

## Use the bar

Click the layout icon to open the menu, then choose a layout. The active layout
has a check mark. **Show Emojis** opens Omarchy's built-in Emojis plugin. The
menu can also open `~/.config/hypr/input.lua` in your editor and show the
keyboard viewer.

Use the arrow keys or `j`/`k` to move through the menu, Enter or Space to
select, and Esc to close.

The bar shows the layout's short code. While the menu is open, it shows a
keyboard icon. Turn on **Show Input Source Name** to keep the full layout name
beside the icon in both states.

![Keyboard icon and input source name while the menu is open](bar-source-name.png)

The plugin uses the layouts and variants already configured in
`~/.config/hypr/input.lua`. For example, `kb_layout = "us,es"` gives you
English (US) and Spanish. With one layout, the indicator stays visible but
there is nothing to switch.

## Add shortcuts

Shortcuts are optional. Add these bindings to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

Tap Ctrl+Space to return to the last layout. Hold Ctrl to see the switcher;
press Space again to cycle, then release Ctrl to close it. Ctrl+Alt+Space moves
to the next configured layout. Use `o.rebind` if your chosen key combination
already has a binding. Ctrl+Space is used by some applications, so choose a
different combination if you need it there.

![Layout switcher with Spanish selected](shortcut-switcher.png)

## Show the keyboard viewer

The viewer appears in the menu by default. Choose **Show Keyboard Viewer**, or run
`omarchy-shell jesusarchive.keyboard-layout-switcher viewer`. The viewer opens
on the focused screen. Click a key to type into the focused application.

![Keyboard viewer with the English (US) layout](keyboard-viewer.png)

- Click Shift, Ctrl, Alt, Super, or AltGr once for the next key. Double-click
  to lock it; click again to turn it off. Ctrl, Alt, and Super can send
  shortcuts such as Ctrl+C. Caps Lock changes the viewer's letter case.
- Click an outlined accent key, then a letter, to compose it. Hold a letter
  to pick an accented form. Hold Backspace, Space, or an arrow to repeat.
- Drag the header to move the viewer and the bottom-right corner to resize it.
  Use the × in the header to close it.

The viewer chooses an ANSI, ISO, ABNT, or JIS shape from the active layout and
keyboard model. You can override the shape in the bar settings.
It does not highlight physical key presses. Its Caps Lock starts in sync with
your keyboard, then changes only the viewer. With Hyprland's default
`follow_mouse`, crossing another window on the way to the viewer can move
keyboard focus to that window.

## Settings

Change settings in the bar editor or with `omarchy bar set`. Boolean values
need `--json` so Omarchy stores a boolean rather than a string.

| Setting | Default | Effect |
| --- | --- | --- |
| `barAppearance` | `icon` | Closed bar icon: `icon`, `bordered`, or `text` |
| `showSourceName` | `false` | Show the full name beside the bar icon |
| `showEmojiAndSymbols` | `true` | Show Omarchy's Emojis picker in the menu; the key retains its old name for existing settings |
| `showKeyboardViewer` | `true` | Show the viewer menu row |
| `showSourceNameMenuItem` | `true` | Show the source-name toggle |
| `showKeyboardSettings` | `true` | Show the input settings action |
| `keyboardViewerGeometry` | `auto` | Advanced: physical viewer shape override (`ansi`, `iso`, `abnt`, or `jis`) |

For example:

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher showSourceName true --json
omarchy bar set jesusarchive.keyboard-layout-switcher keyboardViewerGeometry iso
```

## Commands

Run commands with `omarchy-shell jesusarchive.keyboard-layout-switcher`:

| Command | Action |
| --- | --- |
| `previous` | Return to the last layout; cycle while the switcher is open |
| `next` | Switch to the next configured layout |
| `set es` | Switch by index, code, or layout identifier |
| `current` | Print the active layout code |
| `list` | Print layouts as JSON |
| `toggle` | Toggle the bar menu |
| `viewer` | Toggle the keyboard viewer |

## Update or remove

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

If you added keybindings, remove them from `~/.config/hypr/bindings.lua`. If
you disabled Omarchy's built-in widget, restore it with
`omarchy plugin enable omarchy.keyboard-layout`.

Licensed under [MIT](LICENSE).
