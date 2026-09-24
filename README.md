# Keyboard Layout Switcher

Keyboard layout switcher and interactive keyboard viewer for
[Omarchy Quattro](https://omarchy.org/).

![Layout menu](preview.png)

## Install

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

Uses `hyprctl`, `xkbcli`, `python3`, and `wtype`, included with Omarchy.

## Configuration

Reads keyboard layouts from `~/.config/hypr/input.lua`:

```lua
hl.config({
  input = {
    kb_layout = "us,es",
  },
})
```

Select a layout from the bar menu to switch all detected keyboards.

Appearance and menu options are available in the bar editor. For configuration
from the terminal, see the keys in [manifest.json](manifest.json):

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher barAppearance bordered
omarchy bar set jesusarchive.keyboard-layout-switcher showSourceName true --json
```

## Shortcuts

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

Ctrl+Space switches to the previously used layout. Hold Ctrl and press Space
again to cycle through the switcher. Ctrl+Alt+Space selects the next layout in
configuration order.

![Shortcut switcher](shortcut-switcher.png)

## Keyboard viewer

Choose **Show Keyboard Viewer** from the bar menu. Clicking a key types into the
focused app.

![Keyboard viewer](keyboard-viewer.png)

Click a modifier to apply it to the next key; double-click to lock it. Click again
to release it. Dead keys compose with the next letter, and holding a letter opens
its accent alternatives.

The viewer supports ANSI, ISO, ABNT, and JIS arrangements. Override the automatic
selection with **Keyboard shape** in the bar editor. Physical key presses are
not highlighted.

## Commands

```bash
omarchy-shell jesusarchive.keyboard-layout-switcher <command>
```

| Command | Description |
| --- | --- |
| `previous` | Switch to the previously used layout and start the shortcut switcher |
| `next` | Select the next layout |
| `set <layout>` | Select by XKB identifier, layout code, or zero-based index |
| `current` | Print the current layout code |
| `list` | Print configured layouts and the active selection as JSON |
| `toggle` | Toggle the bar menu on the focused monitor |
| `viewer` | Toggle the keyboard viewer |

Quote variant identifiers, for example `set 'us(intl)'`.

## Update

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
```

## Remove

```bash
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

Remove any bindings you added to `~/.config/hypr/bindings.lua`.

## Development

Run from the repository root on Omarchy with Node.js installed:

```bash
node --test tests/*.test.js
python3 -B -m unittest discover -s tests -p 'test_*.py'
omarchy plugin validate .
```

## License

[MIT](LICENSE)
