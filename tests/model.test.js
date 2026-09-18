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
      { name: "power-button", layout: "us,es", variant: ",", active_layout_index: 1, capsLock: false },
      { name: "hl-virtual-keyboard-fcitx5", layout: "us", variant: "", active_layout_index: 0 },
      Object.assign({ name: "at-translated-set-2-keyboard", layout: "us,es", variant: ",", active_layout_index: 0, capsLock: false }, overrides)
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

test("sources come out in kb_layout order with names", () => {
  const list = Model.sources({ layout: "us,es", variant: "," }, catalog)
  assert.deepStrictEqual(list.map(s => [s.index, s.code, s.name]), [[0, "EN", "English (US)"], [1, "ES", "Spanish"]])
})

test("icon glyphs are the language code, two letters at most", () => {
  const list = Model.sources({ layout: "us,es,us", variant: ",,intl" }, catalog)
  assert.deepStrictEqual(list.map(s => s.glyph), ["EN", "ES", "EN"])
})

test("sources sharing a code get a variant hint", () => {
  const list = Model.sources({ layout: "us,us", variant: ",intl" }, catalog)
  assert.deepStrictEqual(list.map(s => s.code), ["EN", "ENI"])
  assert.strictEqual(list[1].name, "English (US, intl., with dead keys)")
})

test("three sources sharing a code all end up with different codes", () => {
  const list = Model.sources({ layout: "us,us,us", variant: ",intl,dvorak" }, catalog)
  const codes = list.map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "END"])
  assert.strictEqual(new Set(codes).size, 3)
})

test("a taken variant letter moves on to the next letter of the variant", () => {
  const codes = Model.sources({ layout: "us,us,us", variant: ",intl,intl2" }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "ENN"])
})

test("a variant with no letter left falls back to the source position", () => {
  const codes = Model.sources({ layout: "us,us,us", variant: ",i,i" }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "ENI", "EN3"])
})

test("sources with no variant to fall back on still differ", () => {
  const codes = Model.sources({ layout: "us,us", variant: "," }, catalog).map(s => s.code)
  assert.deepStrictEqual(codes, ["EN", "EN2"])
})

test("readDevices ignores buttons and virtual keyboards", () => {
  const state = Model.readDevices(JSON.stringify(devices()), catalog, "")
  assert.deepStrictEqual(state.keyboards, ["at-translated-set-2-keyboard"])
  assert.strictEqual(state.activeIndex, 0)
  assert.strictEqual(state.sources.length, 2)
  assert.strictEqual(state.capsLock, false)
})

test("readDevices reports caps lock and the active layout", () => {
  const state = Model.readDevices(devices({ active_layout_index: 1, capsLock: true }), catalog, "")
  assert.strictEqual(state.activeIndex, 1)
  assert.strictEqual(state.capsLock, true)
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

test("eventKeyboardName splits once and drops the fcitx5 keyboard", () => {
  assert.strictEqual(Model.eventKeyboardName("kbd,English (US, intl., with dead keys)"), "kbd")
  assert.strictEqual(Model.eventKeyboardName("hl-virtual-keyboard-fcitx5,English (US)"), "")
})

test("Ctrl+Space toggles between the two most recent sources", () => {
  let recent = Model.touchRecent([], 0, 3)
  recent = Model.touchRecent(recent, 2, 3)
  assert.deepStrictEqual(recent, [2, 0])
  assert.strictEqual(Model.previousIndex(recent, 2, 3), 0)
  recent = Model.touchRecent(recent, 0, 3)
  assert.strictEqual(Model.previousIndex(recent, 0, 3), 2)
})

test("previousIndex falls back to next without history, and stays put with one source", () => {
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

test("resolveSource accepts an index, a code or a layout", () => {
  const list = Model.sources({ layout: "us,es,us", variant: ",,intl" }, catalog)
  assert.strictEqual(Model.resolveSource(list, "1"), 1)
  assert.strictEqual(Model.resolveSource(list, "es"), 1)
  assert.strictEqual(Model.resolveSource(list, "ES"), 1)
  assert.strictEqual(Model.resolveSource(list, "us(intl)"), 2)
  assert.strictEqual(Model.resolveSource(list, "us"), 0)
  assert.strictEqual(Model.resolveSource(list, "9"), -1)
  assert.strictEqual(Model.resolveSource(list, "fr"), -1)
})

test("switchCommands moves every keyboard with one argv each", () => {
  assert.deepStrictEqual(Model.switchCommands(["a", "b"], 1), [
    ["hyprctl", "switchxkblayout", "a", "1"],
    ["hyprctl", "switchxkblayout", "b", "1"]
  ])
})

test("switchCommands keeps a hostile device name in one argument", () => {
  assert.deepStrictEqual(Model.switchCommands(["evil; dispatch exit"], 0), [
    ["hyprctl", "switchxkblayout", "evil; dispatch exit", "0"]
  ])
})
