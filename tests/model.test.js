const test = require("node:test")
const assert = require("node:assert")
const Model = require("../Model.js")

const XKB = `models:
- name: 'pc105'
  vendor: 'Generic'
  description: Generic 105-key PC

layouts:
- layout: 'us'
  variant: ''
  brief: 'en'
  description: English (US)
  iso639: ['eng']
- layout: 'us'
  variant: 'intl'
  brief: 'en'
  description: English (US, intl., with dead keys)
- layout: 'es'
  variant: ''
  brief: 'es'
  description: Spanish
- layout: 'latam'
  variant: ''
  brief: 'es'
  description: Spanish (Latin American)

option_groups:
- name: 'grp'
  description: Switching to another layout
`

const catalog = Model.layoutCatalog(XKB)

function devices(overrides) {
  return {
    keyboards: [
      { name: "power-button", layout: "us,es", variant: ",", active_layout_index: 1 },
      { name: "hl-virtual-keyboard-fcitx5", layout: "us", variant: "", active_layout_index: 0 },
      Object.assign({ name: "at-translated-set-2-keyboard", layout: "us,es", variant: ",", active_layout_index: 0 }, overrides)
    ]
  }
}

test("catalog reads layouts and variants, skips models and options", () => {
  assert.deepStrictEqual(catalog.us, { brief: "en", description: "English (US)" })
  assert.strictEqual(catalog["us(intl)"].description, "English (US, intl., with dead keys)")
  assert.strictEqual(catalog.es.description, "Spanish")
  assert.strictEqual(catalog.pc105, undefined)
})

test("short codes are xkb language codes, and fall back to the layout name", () => {
  assert.strictEqual(Model.shortCode("us", "", catalog), "EN")
  assert.strictEqual(Model.shortCode("es", "", catalog), "ES")
  assert.strictEqual(Model.shortCode("latam", "", catalog), "ES")
  assert.strictEqual(Model.shortCode("xx", "", {}), "XX")
})

test("layouts come out in kb_layout order with names", () => {
  const list = Model.layouts({ layout: "us,es", variant: "," }, catalog)
  assert.deepStrictEqual(list.map(s => [s.index, s.code, s.name]), [[0, "EN", "English (US)"], [1, "ES", "Spanish"]])
})

test("icon glyphs are the language code, two letters at most", () => {
  const list = Model.layouts({ layout: "us,es,us", variant: ",,intl" }, catalog)
  assert.deepStrictEqual(list.map(s => s.glyph), ["EN", "ES", "EN"])
})

test("layouts sharing a code get a variant hint", () => {
  const list = Model.layouts({ layout: "us,us", variant: ",intl" }, catalog)
  assert.deepStrictEqual(list.map(s => s.code), ["EN", "ENI"])
  assert.strictEqual(list[1].name, "English (US, intl., with dead keys)")
})

test("three layouts sharing a code all end up with different codes", () => {
  const list = Model.layouts({ layout: "us,us,us", variant: ",intl,dvorak" }, catalog)
  const codes = list.map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "END"])
  assert.strictEqual(new Set(codes).size, 3)
})

test("a taken variant letter moves on to the next letter of the variant", () => {
  const codes = Model.layouts({ layout: "us,us,us", variant: ",intl,intl2" }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "ENN"])
})

test("a variant with no letter left falls back to the layout position", () => {
  const codes = Model.layouts({ layout: "us,us,us", variant: ",i,i" }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "EN3"])
})

test("layouts with no variant to fall back on still differ", () => {
  const codes = Model.layouts({ layout: "us,us", variant: "," }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "EN2"])
})

test("readDevices ignores buttons and virtual keyboards", () => {
  const state = Model.readDevices(JSON.stringify(devices()), catalog, "")
  assert.deepStrictEqual(state.keyboards, ["at-translated-set-2-keyboard"])
  assert.strictEqual(state.activeIndex, 0)
  assert.strictEqual(state.layouts.length, 2)
})

test("readDevices reports the active layout", () => {
  const state = Model.readDevices(devices({ active_layout_index: 1 }), catalog, "")
  assert.strictEqual(state.activeIndex, 1)
})

test("readDevices passes the selected keyboard's XKB model and options to the viewer", () => {
  const state = Model.readDevices(devices({ model: "pc105", options: "compose:caps" }), catalog, "")
  assert.strictEqual(state.keyboardModel, "pc105")
  assert.strictEqual(state.keyboardOptions, "compose:caps")
})

test("readDevices rejects garbage", () => {
  assert.strictEqual(Model.readDevices("", catalog, ""), null)
  assert.strictEqual(Model.readDevices("not json", catalog, ""), null)
})

test("selectKeyboard prefers the keyboard the event named", () => {
  const typed = [{ name: "a", active_layout_index: 1 }, { name: "b", active_layout_index: 0 }]
  assert.strictEqual(Model.selectKeyboard(typed, "b").name, "b")
  assert.strictEqual(Model.selectKeyboard(typed, "").name, "a")
  assert.strictEqual(Model.selectKeyboard([], ""), null)
})

test("selectKeyboard falls back to the device Hyprland marks main", () => {
  // A ThinkPad reports the headphone jack and the extra-button row as keyboards
  // carrying the same layout list. Without `main`, the furthest-advanced index
  // lets one of those answer for the keyboard.
  const typed = [
    { name: "sof-hda-dsp-headphone", active_layout_index: 1, main: false },
    { name: "at-translated-set-2-keyboard", active_layout_index: 0, main: true }
  ]
  assert.strictEqual(Model.selectKeyboard(typed, "").name, "at-translated-set-2-keyboard")
})

test("selectKeyboard puts the named keyboard ahead of the main one", () => {
  const typed = [
    { name: "usb-keyboard", active_layout_index: 0, main: false },
    { name: "at-translated-set-2-keyboard", active_layout_index: 0, main: true }
  ]
  assert.strictEqual(Model.selectKeyboard(typed, "usb-keyboard").name, "usb-keyboard")
})

test("eventKeyboardName splits once and drops the fcitx5 keyboard", () => {
  assert.strictEqual(Model.eventKeyboardName("kbd,English (US, intl., with dead keys)"), "kbd")
  assert.strictEqual(Model.eventKeyboardName("hl-virtual-keyboard-fcitx5,English (US)"), "")
})

test("Ctrl+Space toggles between the two most recent layouts", () => {
  let recent = Model.touchRecent([], 0, 3)
  recent = Model.touchRecent(recent, 2, 3)
  assert.deepStrictEqual(recent, [2, 0])
  assert.strictEqual(Model.previousIndex(recent, 2, 3), 0)
  recent = Model.touchRecent(recent, 0, 3)
  assert.strictEqual(Model.previousIndex(recent, 0, 3), 2)
})

test("previousIndex falls back to next without history, and stays put with one layout", () => {
  assert.strictEqual(Model.previousIndex([0], 0, 2), 1)
  assert.strictEqual(Model.previousIndex([], 0, 1), 0)
})

test("touchRecent drops indices that no longer exist", () => {
  assert.deepStrictEqual(Model.touchRecent([3, 1, 0], 1, 2), [1, 0])
})

test("nextIndex cycles forward and wraps", () => {
  assert.strictEqual(Model.nextIndex(0, 3), 1)
  assert.strictEqual(Model.nextIndex(2, 3), 0)
  assert.strictEqual(Model.nextIndex(0, 1), 0)
})

test("resolveLayout accepts an index, a code or a layout", () => {
  const list = Model.layouts({ layout: "us,es,us", variant: ",,intl" }, catalog)
  assert.strictEqual(Model.resolveLayout(list, "1"), 1)
  assert.strictEqual(Model.resolveLayout(list, "es"), 1)
  assert.strictEqual(Model.resolveLayout(list, "ES"), 1)
  assert.strictEqual(Model.resolveLayout(list, "us(intl)"), 2)
  assert.strictEqual(Model.resolveLayout(list, "us"), 0)
  assert.strictEqual(Model.resolveLayout(list, "9"), -1)
  assert.strictEqual(Model.resolveLayout(list, "fr"), -1)
})

test("switchCommands moves every keyboard with one argv each", () => {
  assert.deepStrictEqual(Model.switchCommands(["a", "b"], 1), [
    ["hyprctl", "switchxkblayout", "a", "1"],
    ["hyprctl", "switchxkblayout", "b", "1"]
  ])
})

test("switchCommands keeps special characters in one argument", () => {
  assert.deepStrictEqual(Model.switchCommands(["evil; dispatch exit"], 0), [
    ["hyprctl", "switchxkblayout", "evil; dispatch exit", "0"]
  ])
})

test("readDevices reports Caps Lock when any keyboard has it on", () => {
  assert.strictEqual(Model.readDevices(devices(), catalog, "").capsLock, false)
  assert.strictEqual(Model.readDevices(devices({ capsLock: true }), catalog, "").capsLock, true)
})

test("activelayout events from virtual keyboards are recognised", () => {
  assert.strictEqual(Model.isVirtualKeyboardEvent("hl-virtual-keyboard-wtype,English (US)"), true)
  assert.strictEqual(Model.isVirtualKeyboardEvent("hl-virtual-keyboard-fcitx5,error"), true)
  assert.strictEqual(Model.isVirtualKeyboardEvent("at-translated-set-2-keyboard,Spanish"), false)
})
