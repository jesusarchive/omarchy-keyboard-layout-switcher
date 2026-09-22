# Keyboard Layout Switcher for Omarchy

A keyboard layout menu for the [Omarchy](https://omarchy.org) bar. The bar shows
the active keyboard layout as a small badge (`EN`, `ES`). Click it for the layouts
menu, or bind Ctrl+Space to go straight back to the layout you used before and
Ctrl+Alt+Space to step forward through them.
Plugin ID: `jesusarchive.keyboard-layout-switcher`. MIT licensed.

![The EN badge in the bar with the layouts menu open, listing English (US) and Spanish](preview.png)

- The bar badge carries the layout's language code from xkb. Hover it for the
  full name ("Spanish"), or turn on "Show Input Source Name" in the menu to
  keep the name next to the badge.
- The layouts menu lists every layout with a ✓ on the active one, then "Show
  Emoji & Symbols" (Omarchy's emoji picker), "Show Keyboard Viewer", "Show
  Input Source Name", and "Open Keyboard Settings…" (`~/.config/hypr/input.lua`).
- The keyboard viewer floats above apps and follows the active layout. Click
  Shift or AltGr to see those symbols, and click a key to type into the focused
  app. On a physical keyboard, use Shift or Right Alt (AltGr), or both, with the
  key shown. Accent keys marked in the theme accent color are dead keys: press
  one and then a letter. Hold an on-screen letter to pick an accented version.
  Drag the strip above the keys to move the viewer, or
  close it with the × button. The viewer does not yet track held physical
  modifiers. Its on-screen Caps key
  changes only the viewer's letters; it does not change your physical Caps or
  Compose setting.
- Ctrl+Space on its own switches to the most recently used layout and shows
  nothing. Keep Ctrl down instead and the switcher appears, listing every
  layout. Tap Space with Ctrl still down to walk the list, and let go to settle
  on whichever layout you landed on.
- Ctrl+Alt+Space steps to the next layout in order and shows nothing.
- Every keyboard switches together, so a second keyboard never stays on the old
  layout. The plugin ignores virtual keyboards and ACPI buttons.
- The badge, the menu and the switcher use Omarchy's menu colors and fonts.
- A menu pick or a scripted switch shows no overlay. The bar badge changes, and
  that is the only report.

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
- Names and codes come from `xkbcli list`, read once at start. `es` becomes
  "Spanish" and `ES`. Two layouts with the same code (`us` and `us(intl)`) get a
  variant letter so their badges differ.
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

## License

MIT
