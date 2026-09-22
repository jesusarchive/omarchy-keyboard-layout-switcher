# Keyboard Layout Switcher for Omarchy

A keyboard layout menu for the [Omarchy](https://omarchy.org) bar. The bar shows
the active keyboard layout as a small badge (`EN`, `ES`). Click it for the layouts
menu, or bind Ctrl+Space to go straight back to the layout you used before and
Ctrl+Alt+Space to step forward through them.
Plugin ID: `jesusarchive.keyboard-layout-switcher`. MIT licensed.

![The keyboard layout menu and bar on an empty Omarchy workspace](preview.png)

- The bar shows the layout's short language code from xkb (`EN`, `ES`). Choose
  a filled icon, bordered badge, or plain text in the widget settings. Hover
  it for the full name ("Spanish"), or turn on "Show Input Source Name" in the
  menu to keep the name next to the code. The bar shows a keyboard icon while
  the menu is open.
- The layouts menu lists every layout with a ✓ on the active one. Its optional
  rows open Omarchy's Emoji & Symbols picker, show the Keyboard Viewer, toggle
  the source name in the bar, and open Keyboard Settings
  (`~/.config/hypr/input.lua`). Each optional row can be hidden in the plugin
  settings.
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
- The badge, the menu and the switcher use Omarchy's menu colors and fonts.
- Menu picks and the `set` and `next` commands change the bar badge without an
  overlay. The `previous` shortcut can show the switcher when Ctrl stays held.

## Shortcut switcher

![The Ctrl+Space switcher listing English and Spanish](shortcut-switcher.png)

## Keyboard viewer (beta)

![The keyboard viewer showing the English (US) layout](keyboard-viewer.png)

## Install

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
omarchy plugin enable jesusarchive.keyboard-layout-switcher
```

Requirements: `hyprctl`, `xkbcli`, `wtype`, Python 3 and libxkbcommon. All ship with Omarchy.

### Bar appearance and menu options

Set `barAppearance` to `icon` (the current filled badge), `bordered` (an outline
around the code), or `text` (the code alone). The default is `icon`.
`showSourceName` independently adds the full layout name beside any of these.

The widget settings include a switch for each optional menu row. All four rows
are shown by default; turn off any of these settings to remove its row:

| Setting | Menu row |
|---|---|
| `showEmojiAndSymbols` | Show Emoji & Symbols |
| `showKeyboardViewer` | Show Keyboard Viewer |
| `showSourceNameMenuItem` | Show Input Source Name |
| `showKeyboardSettings` | Open Keyboard Settings… |

The bar name setting still works when its menu row is hidden. If you edit
`~/.config/omarchy/shell.json` directly, add `barAppearance` or any of these
keys to the widget's entry. Set menu row keys to `false` to hide them.
The layout choices and keyboard shortcuts remain available.

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

To use other keys, change the first argument, for example `"SUPER + SPACE"`. If
Omarchy or another plugin already binds the chord you pick, add
`hl.unbind("SUPER + SPACE")` on the line before, then check with
`hyprctl configerrors`.

### Remove

```bash
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

Then delete the binding from `bindings.lua`.

## Use

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

## How it works

- `Service.qml` runs once for the whole shell. It reads `hyprctl -j devices`
  on start and on every `activelayout` and `configreloaded` event from
  Hyprland, owns the IPC target, and draws the switcher in `SwitchHud.qml`.
  The switcher opens on the monitor that has focus and stays on it until it
  closes, so moving focus mid-switch cannot make a card that is already up jump
  to another screen.
- Switching runs one detached `hyprctl switchxkblayout <keyboard> <index>` per
  typed keyboard. Each device name goes in its own argument, so no shell or
  batch separator can split it.
- With two or more layouts the service re-reads the device list every 10
  seconds, because plugging a keyboard in raises no Hyprland event. A
  single-layout install has nothing to switch, so the service skips the poll.
- Names and short language codes come from `xkbcli list`, read once at start.
  `us` becomes `EN`; `es` becomes `ES` with the name "Spanish". Two entries
  with the same code (`us` and `us(intl)`) get a variant letter so their
  badges differ.
- Ctrl+Space keeps a most-recently-used list, and a run of presses while the
  switcher is up counts as one use.
- A Ctrl+Space takes the keyboard straight away and draws nothing. That grab is
  the only way to learn that the modifier came back up, because a Hyprland
  binding reports the press and never the release. A release inside
  a quarter of a second ends the run having shown nothing, and the switch has
  already happened. Past that, the switcher appears.
- While it is up, Space reaches the switcher directly and the switcher walks the
  list, so a binding that fires for the same press is dropped. If the grab never
  takes, the binding drives the list as before and the switcher closes after
  five seconds of silence. Any key that is not Space hands the keyboard
  straight back.
- `Widget.qml` is the bar badge and menu, one per monitor. It only renders what
  the service exposes.
- `KeyboardViewer.qml` draws the floating keyboard. `keyboard_viewer.py` reads
  each key's symbols from libxkbcommon for the active layout and modifiers.
- `Model.js` holds the parsing and switching logic with no Qt imports, so node
  can test it.

## Development

```bash
node --test tests/*.test.js               # model tests
omarchy plugin validate .                 # manifest check
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/jesusarchive.keyboard-layout-switcher/
omarchy restart shell                     # QML changes need a restart to show up
omarchy-shell jesusarchive.keyboard-layout-switcher list
```

Files:
- `manifest.json`
- `Service.qml`: the layout state, the switching and the IPC target
- `SwitchHud.qml`: the switcher overlay
- `Widget.qml`: the bar badge and the layouts menu
- `LayoutIcon.qml`: the badge drawing
- `KeyboardViewer.qml`, `keyboard_viewer.py`, and `Typing.js`: the keyboard map,
  XKB labels, and dead-key composition
- `Model.js`: the pure logic
- `tests/`: the node tests
- `preview.png`: the marketplace preview, also the image above
- `shortcut-switcher.png` and `keyboard-viewer.png`: README screenshots

## License

MIT
