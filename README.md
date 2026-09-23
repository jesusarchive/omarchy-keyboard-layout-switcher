# Keyboard Layout Switcher for Omarchy

Click the layout indicator in the [Omarchy](https://omarchy.org) bar to choose a
keyboard layout. Optional shortcuts switch layouts without opening the menu.

![Keyboard layout menu in the Omarchy bar](preview.png)

## Requirements

Omarchy Quattro with shell plugin support. Omarchy includes the tools this plugin
uses: `hyprctl`, `xkbcli`, `wtype`, Python 3, and libxkbcommon.

## Installation

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

The indicator starts in the right section of the bar. To move it:

```bash
omarchy bar move jesusarchive.keyboard-layout-switcher --section center
```

## Configuration

### Keyboard layouts

The plugin switches between layouts configured in `~/.config/hypr/input.lua`.
For example:

```lua
kb_layout = "us,es",
kb_variant = ",",
```

With one layout, the indicator remains visible but there is nothing to switch.

### Shortcuts

The plugin does not install keybindings. Add these to
`~/.config/hypr/bindings.lua` if you want them:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

Tap Ctrl+Space to return to the last used layout. Keep Ctrl held to show the
switcher, then press Space to cycle through the layouts. Ctrl+Alt+Space moves to
the next layout in the configured order.

![Keyboard layout switcher](shortcut-switcher.png)

These chords are unbound in Omarchy by default. A binding for Ctrl+Space will
take that shortcut away from applications that use it. To choose another chord,
change the first argument. Use `o.rebind` instead of `o.bind` if that chord is
already bound.

### Bar and menu

The bar shows a short language code from xkb, such as `EN` or `ES`. The default
style is a filled badge. Choose `bordered` for an outline or `text` for plain
text, and optionally show the full layout name beside it:

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher barAppearance bordered
omarchy bar set jesusarchive.keyboard-layout-switcher showSourceName true --json
```

The menu also offers Emoji & Symbols, the Keyboard Viewer, a source-name toggle,
and an action that opens `~/.config/hypr/input.lua` in your editor. Hide any of
those rows by setting its key to `false`:

| Key | Menu row |
| --- | --- |
| `showEmojiAndSymbols` | Show Emoji & Symbols |
| `showKeyboardViewer` | Show Keyboard Viewer |
| `showSourceNameMenuItem` | Show Input Source Name |
| `showKeyboardSettings` | Open Keyboard Settings… |

For example:

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher showKeyboardViewer false --json
```

Use `--json` for boolean values so Omarchy stores `true` or `false` instead of
strings.

## Usage

Left or right click the bar indicator to open the menu. Select a layout to
switch every connected keyboard. The menu supports Omarchy's usual panel keys:
arrows or `j`/`k` to move, Enter or Space to select, and Esc to close.

### Keyboard viewer (beta)

Choose **Show Keyboard Viewer** from the menu to open a floating keyboard for
the active layout. Click keys to type into the focused application. The on-screen
Shift and AltGr keys change the symbols shown; accent keys work as dead keys,
and holding a letter shows accented choices. Drag the strip above the keys to
move the viewer, or close it with the × at the top right.

The viewer is in beta. It does not track held physical modifiers, and its
on-screen Caps key changes only the viewer.

![Keyboard Viewer showing the English (US) layout](keyboard-viewer.png)

### Commands

The plugin exposes these commands through `omarchy-shell`:

| Command | Action |
| --- | --- |
| `previous` | Switch to the last used layout |
| `next` | Switch to the next configured layout |
| `set es` | Switch by index, code, or layout identifier |
| `current` | Print the active layout code |
| `list` | Print layouts as JSON |
| `toggle` | Open the menu on the focused monitor |
| `viewer` | Toggle the Keyboard Viewer |
| `refresh` | Read the current layout again |

For example:

```bash
omarchy-shell jesusarchive.keyboard-layout-switcher set es
```

## Updating

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
```

## Removal

```bash
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

Remove any keybindings you added to `~/.config/hypr/bindings.lua`.

## License

[MIT](LICENSE)
