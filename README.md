# Keyboard Layout Switcher

Switch keyboard layouts from the Omarchy bar. The plugin reads
`~/.config/hypr/input.lua` and switches all connected keyboards together.

![Keyboard layout menu with English and Spanish](preview.png)

## Install

Requires Omarchy Quattro.

```bash
omarchy plugin add https://github.com/jesusarchive/omarchy-keyboard-layout-switcher.git --enable
```

## Use

Click the bar icon and choose a layout. A check mark shows the active layout.
The menu also opens Omarchy's Emojis picker, the keyboard viewer, and
`~/.config/hypr/input.lua` in your editor. Use **Show Input Source Name** to
display the full layout name in the bar.

Use the arrow keys or `j`/`k` to move through the menu, Enter to select, and
Esc to close.

![Keyboard icon and input source name while the menu is open](bar-source-name.png)

For example, `kb_layout = "us,es"` in `~/.config/hypr/input.lua` gives you
English (US) and Spanish.

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

## Keyboard viewer

Choose **Show Keyboard Viewer** from the menu. Click its keys to type.

![Keyboard viewer with the English (US) layout](keyboard-viewer.png)

- Click Shift, Ctrl, Alt, Super, or AltGr once for the next key. Double-click
  to lock it; click again to turn it off. Caps Lock toggles letter case.
- Click an outlined accent key, then a letter, to compose it. Hold a letter to
  choose an accented form.
- Drag the header to move the viewer, use the bottom-right corner to resize it,
  and click × to close it.

The viewer types into the app that has keyboard focus. It does not highlight
physical key presses. If its shape does not match your keyboard, change
**Keyboard Viewer Shape** in the bar editor.

## Update or remove

```bash
omarchy plugin update jesusarchive.keyboard-layout-switcher
omarchy plugin remove jesusarchive.keyboard-layout-switcher
```

If you added keybindings, remove them from `~/.config/hypr/bindings.lua` when
you remove the plugin.

Licensed under [MIT](LICENSE).
