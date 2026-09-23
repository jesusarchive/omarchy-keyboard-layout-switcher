# Keyboard Layout Switcher for Omarchy

A keyboard layout menu for the [Omarchy](https://omarchy.org) bar. The bar shows
the active keyboard layout as a small badge (`EN`, `ES`). Click it for the layouts
menu, or bind Ctrl+Space to go straight back to the layout you used before and
Ctrl+Alt+Space to step forward through them.
Plugin ID: `jesusarchive.keyboard-layout-switcher`. MIT licensed.

![The keyboard layout menu and bar on an empty Omarchy workspace](preview.png)

- The bar shows the layout's short language code from xkb (`EN`, `ES`). Choose
  a filled icon, bordered badge, or plain text. Hover for the full name
  ("Spanish"), or turn on "Show Input Source Name" in the menu to keep it beside
  the code. The bar shows a keyboard icon while the menu is open.
- The layouts menu lists every layout with a ✓ on the active one. Its optional
  rows open Omarchy's Emoji & Symbols picker, show the Keyboard Viewer, toggle
  the source name in the bar, and open Keyboard Settings
  (`~/.config/hypr/input.lua`). Each optional row can be hidden.
- The keyboard viewer is in beta. It follows the active layout and lets you
  click keys to type into the focused app. Click Shift or AltGr to see their
  symbols. Accent keys act as dead keys; hold a letter for accented choices.
  Drag the strip above the keys to move the viewer. It does not yet track held
  physical modifiers. Its on-screen Caps key affects only the viewer.
- Ctrl+Space on its own switches to the most recently used layout and shows
  nothing. Keep Ctrl down instead and the switcher appears, listing every
  layout. Tap Space with Ctrl still down to walk the list, and let go to settle
  on whichever layout you landed on.
- Ctrl+Alt+Space steps to the next layout in order and shows nothing.
- Every keyboard switches together, so a second keyboard never stays on the old
  layout. The plugin ignores virtual keyboards and ACPI buttons.
- The badge uses the bar colors; the menu and switcher use Omarchy's menu colors
  and fonts.
- Menu picks and the `set` and `next` commands change the bar badge without an
  overlay. The `previous` shortcut can show the switcher when Ctrl stays held.

## Shortcut switcher

![The Ctrl+Space switcher listing English and Spanish](shortcut-switcher.png)

## Keyboard viewer (beta)

![The keyboard viewer showing the English (US) layout](keyboard-viewer.png)

## Requirements

Omarchy Quattro with shell plugin support. The plugin uses `hyprctl`, `xkbcli`,
`wtype`, Python 3 and libxkbcommon, which Omarchy includes.

## Installation

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

The widget lands in the right section of the bar. Move it with
`omarchy bar move jesusarchive.keyboard-layout-switcher --section <left|center|right>`.

Manual install from a checkout:

```bash
omarchy plugin validate .
mkdir -p ~/.config/omarchy/plugins/jesusarchive.keyboard-layout-switcher
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/jesusarchive.keyboard-layout-switcher/
omarchy-shell shell rescanPlugins
omarchy plugin enable jesusarchive.keyboard-layout-switcher
```

## Configuration

### Bar appearance and menu options

Set `barAppearance` to `icon` (the default filled badge), `bordered` (an outline),
or `text` (the code alone). `showSourceName` adds the full layout name beside
any style. For example:

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher barAppearance bordered
omarchy bar set jesusarchive.keyboard-layout-switcher showSourceName true --json
```

All four optional menu rows appear by default. Set a row's key to `false` to
hide it:

| Setting | Menu row |
|---|---|
| `showEmojiAndSymbols` | Show Emoji & Symbols |
| `showKeyboardViewer` | Show Keyboard Viewer |
| `showSourceNameMenuItem` | Show Input Source Name |
| `showKeyboardSettings` | Open Keyboard Settings… |

```bash
omarchy bar set jesusarchive.keyboard-layout-switcher showKeyboardViewer false --json
```

Use `--json` for `true` and `false`; otherwise `omarchy bar set` stores them as
strings. These settings live on the widget's entry in
`~/.config/omarchy/shell.json`. Hiding the name toggle leaves the current bar
name setting intact. The layout choices and keyboard shortcuts remain available.

### Layouts

The plugin only moves between layouts you already have. List two or more in
`~/.config/hypr/input.lua`:

```lua
kb_layout = "us,es",
kb_variant = ",",
```

With a single layout the badge still shows, and switching does nothing.

### Keybindings

The plugin doesn't bind any keys. Add these two lines to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + SPACE", "Previous keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher previous")
o.bind("CTRL + ALT + SPACE", "Next keyboard layout", "omarchy-shell jesusarchive.keyboard-layout-switcher next")
```

| Chord | Action |
|---|---|
| Ctrl+Space, released at once | go back to the layout you used before, showing nothing |
| Ctrl+Space, Ctrl kept down | the same switch, and the switcher appears |
| Ctrl held, Space again | move down the list |
| Ctrl released | close the switcher on the layout you landed on |
| Ctrl+Alt+Space | step to the next layout in order, with no switcher |

Hyprland reloads the file on save, and both bindings show up in Omarchy's
keybindings list (Super+K). Omarchy claims neither chord. It uses Super+Space
for its own menu, so nothing needs unbinding first. Apps that want Ctrl+Space,
editor completion for example, stop receiving it.

To use other keys, change the first argument. If the chord is already bound,
use `o.rebind` in place of `o.bind`, then check `hyprctl configerrors`.

## Usage

| Where | Action |
|---|---|
| Bar: left or right click | open the layouts menu |
| Menu: click a layout | switch to it |
| Menu: Show Keyboard Viewer | toggle the floating keyboard map |

Keys while the menu is open:

| Key | Action |
|---|---|
| `j` / `k` / arrows | move |
| `Enter` / `Space` | activate the selected row |
| `Tab` / `Shift+Tab` | next or previous bar panel |
| `Esc` | close |

These come from Omarchy's shared panel key handling, so they are the same keys
every other bar panel uses. The menu opens with the highlight hidden and the
cursor already on the active layout, so the first key press reveals it without
moving.

### Scripting

The plugin registers an IPC target:

```bash
omarchy-shell jesusarchive.keyboard-layout-switcher previous   # the layout used before this one
omarchy-shell jesusarchive.keyboard-layout-switcher next       # the next layout in order
omarchy-shell jesusarchive.keyboard-layout-switcher set es     # by index, code (ES) or layout (es, us(intl))
omarchy-shell jesusarchive.keyboard-layout-switcher current    # prints the active code, e.g. EN
omarchy-shell jesusarchive.keyboard-layout-switcher list       # JSON of every layout
omarchy-shell jesusarchive.keyboard-layout-switcher toggle     # open the menu on the focused monitor
omarchy-shell jesusarchive.keyboard-layout-switcher viewer     # toggle the keyboard viewer
omarchy-shell jesusarchive.keyboard-layout-switcher refresh
```

`previous` and `next` print the new code, or `single` when there's only one
layout. `set` prints `unknown` for a layout that doesn't exist.

## Updating

Update a GitHub installation with:

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
```

## Removal

```bash
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

Remove any bindings you added to `~/.config/hypr/bindings.lua`.

## Development

```bash
node --test tests/*.test.js
qmllint -I /usr/share/omarchy/shell *.qml
omarchy plugin validate .
```

## License

[MIT](LICENSE)
