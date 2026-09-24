const test = require("node:test")
const assert = require("node:assert")
const Typing = require("../Typing.js")

// A small keymap in the shape keyboard_viewer.py prints: eight states per key
// (1 = Shift, 2 = Caps Lock, 4 = AltGr), Compose results and accents.
function ch(text, keysym) { return { keysym: keysym || text, label: text, text: text, dead: "" } }
function dead(name, label) { return { keysym: name, label: label, text: "", dead: name } }

const keymap = {
  keys: {
    // Spanish E: Caps Lock does not reach the AltGr levels.
    AD03: { states: [ch("e"), ch("E"), ch("E"), ch("e"), ch("€", "EuroSign"), ch("¢", "cent"), ch("€", "EuroSign"), ch("¢", "cent")] },
    AB03: { states: [ch("c"), ch("C"), ch("C"), ch("c"), ch("©", "copyright"), ch("©", "copyright"), ch("©", "copyright"), ch("©", "copyright")] },
    AB02: { states: [ch("x"), ch("X"), ch("X"), ch("x"), null, null, null, null] },
    AE01: { states: [ch("1"), ch("!", "exclam"), ch("1"), ch("!", "exclam"), ch("|", "bar"), ch("¡", "exclamdown"), ch("|", "bar"), ch("¡", "exclamdown")] },
    AC11: { states: [dead("dead_acute", "´"), dead("dead_diaeresis", "¨"), dead("dead_acute", "´"), dead("dead_diaeresis", "¨"),
      ch("{", "braceleft"), dead("dead_doubleacute", "˝"), ch("{", "braceleft"), dead("dead_doubleacute", "˝")] }
  },
  compose: {
    dead_acute: { e: "é", E: "É", space: "'", dead_acute: "´" },
    dead_diaeresis: { e: "ë", space: "\"" }
  },
  accents: { e: ["è", "é", "ê", "ë"], c: ["ç", "ć"] },
  altGrKey: "RALT"
}

function run(state, ids, start) {
  let now = start || 0
  const commands = []
  for (const id of ids) {
    const result = Typing.press(keymap, state, id, now)
    state = result.state
    commands.push(...result.commands)
    now += 1000
  }
  return { state, commands }
}

const fresh = () => Typing.initialState(false)

test("a letter types its text", () => {
  assert.deepStrictEqual(run(fresh(), ["AD03"]).commands, [["wtype", "--", "e"]])
})

test("Shift latches for one key, then releases", () => {
  const { state, commands } = run(fresh(), ["LFSH", "AD03", "AD03"])
  assert.deepStrictEqual(commands, [["wtype", "--", "E"], ["wtype", "--", "e"]])
  assert.strictEqual(state.shift, 0)
})

test("both Shift keys drive the same state", () => {
  assert.strictEqual(Typing.modifierFor("LFSH", keymap), "shift")
  assert.strictEqual(Typing.modifierFor("RTSH", keymap), "shift")
})

test("a quick second click locks Shift, and a third click turns it off", () => {
  let state = Typing.press(keymap, fresh(), "LFSH", 1000).state
  state = Typing.press(keymap, state, "RTSH", 1200).state
  assert.strictEqual(state.shift, Typing.LOCKED)
  const typed = run(state, ["AD03", "AD03"], 5000)
  assert.deepStrictEqual(typed.commands, [["wtype", "--", "E"], ["wtype", "--", "E"]])
  assert.strictEqual(Typing.press(keymap, typed.state, "LFSH", 9000).state.shift, 0)
})

test("Ctrl, Alt, Super and AltGr latch, lock, and turn off", () => {
  for (const [id, name] of [["LCTL", "ctrl"], ["LALT", "alt"], ["LWIN", "logo"], ["RALT", "altgr"]]) {
    let state = Typing.press(keymap, fresh(), id, 1000).state
    assert.strictEqual(state[name], Typing.LATCHED, id)
    state = Typing.press(keymap, state, id, 1200).state
    assert.strictEqual(state[name], Typing.LOCKED, id)
    state = Typing.press(keymap, state, "AD03", 1300).state
    assert.strictEqual(state[name], Typing.LOCKED, id)
    state = Typing.press(keymap, state, id, 2000).state
    assert.strictEqual(state[name], 0, id)
  }
})

test("a slow second click turns a latched modifier off instead of locking it", () => {
  let state = Typing.press(keymap, fresh(), "LFSH", 1000).state
  state = Typing.press(keymap, state, "LFSH", 1000 + Typing.LOCK_CLICK_MS + 1).state
  assert.strictEqual(state.shift, 0)
})

test("latching another modifier in between does not lock the first", () => {
  let state = Typing.press(keymap, fresh(), "LFSH", 1000).state
  state = Typing.press(keymap, state, "LCTL", 1100).state
  state = Typing.press(keymap, state, "LFSH", 1200).state
  assert.strictEqual(state.shift, 0)
  assert.strictEqual(state.ctrl, Typing.LATCHED)
})

test("Caps Lock toggles and follows the key type", () => {
  const caps = Typing.press(keymap, fresh(), "CAPS", 0).state
  assert.strictEqual(caps.caps, true)
  assert.deepStrictEqual(run(caps, ["AD03", "AE01"]).commands, [["wtype", "--", "E"], ["wtype", "--", "1"]])
})

test("Caps Lock with AltGr types what a real Spanish keyboard types", () => {
  const state = run(Typing.initialState(true), ["RALT"]).state
  assert.deepStrictEqual(run(state, ["AD03"]).commands, [["wtype", "--", "€"]])
})

test("the viewer's Caps Lock works whatever the physical key is mapped to", () => {
  assert.strictEqual(Typing.press(keymap, fresh(), "CAPS", 0).state.caps, true)
})

test("Right Alt is AltGr only when the layout has a third level", () => {
  assert.strictEqual(Typing.modifierFor("RALT", keymap), "altgr")
  assert.strictEqual(Typing.modifierFor("RALT", Object.assign({}, keymap, { altGrKey: "" })), "alt")
  assert.strictEqual(Typing.modifierFor("RALT", Object.assign({}, keymap, { altGrKey: "CAPS" })), "alt")
})

test("dead keys compose through the Compose table", () => {
  assert.deepStrictEqual(run(fresh(), ["AC11", "AD03"]).commands, [["wtype", "--", "é"]])
  assert.deepStrictEqual(run(fresh(), ["AC11", "LFSH", "AD03"]).commands, [["wtype", "--", "É"]])
})

test("a dead key then Space types what Compose says, not the spacing accent", () => {
  assert.deepStrictEqual(run(fresh(), ["AC11", "SPCE"]).commands, [["wtype", "--", "'"]])
  assert.deepStrictEqual(run(fresh(), ["LFSH", "AC11", "SPCE"]).commands, [["wtype", "--", "\""]])
})

test("the same dead key twice types the accent", () => {
  assert.deepStrictEqual(run(fresh(), ["AC11", "AC11"]).commands, [["wtype", "--", "´"]])
})

test("a dead key followed by a key it cannot compose with types both", () => {
  assert.deepStrictEqual(run(fresh(), ["AC11", "AB02"]).commands, [["wtype", "--", "'x"]])
})

test("Esc and Backspace cancel a pending dead key", () => {
  const cancelled = run(fresh(), ["AC11", "ESC"])
  assert.deepStrictEqual(cancelled.commands, [])
  assert.strictEqual(cancelled.state.dead, "")
  assert.deepStrictEqual(run(fresh(), ["AC11", "BKSP"]).commands, [])
})

test("Return after a dead key types the accent, then Return", () => {
  assert.deepStrictEqual(run(fresh(), ["AC11", "RTRN"]).commands, [["wtype", "--", "'"], ["wtype", "-k", "Return"]])
})

test("the dead key that is waiting is remembered for the highlight", () => {
  const state = run(fresh(), ["AC11"]).state
  assert.strictEqual(state.dead, "dead_acute")
  assert.strictEqual(state.deadId, "AC11")
})

test("Ctrl sends a shortcut in one wtype call and then releases", () => {
  const { state, commands } = run(fresh(), ["LCTL", "AB03"])
  assert.deepStrictEqual(commands, [["wtype", "-M", "ctrl", "-k", "c", "-m", "ctrl"]])
  assert.strictEqual(state.ctrl, 0)
})

test("Ctrl+Shift sends the base key with Shift held, like a physical keyboard", () => {
  assert.deepStrictEqual(run(fresh(), ["LCTL", "LFSH", "AB03"]).commands,
    [["wtype", "-M", "ctrl", "-M", "shift", "-k", "c", "-m", "shift", "-m", "ctrl"]])
})

test("Shift with a special key sends the chord", () => {
  assert.deepStrictEqual(run(fresh(), ["LFSH", "TAB"]).commands, [["wtype", "-M", "shift", "-k", "Tab", "-m", "shift"]])
})

test("action keys send their own keysyms", () => {
  const keys = { ESC: "Escape", BKSP: "BackSpace", TAB: "Tab", RTRN: "Return",
    SPCE: "space", LEFT: "Left", UP: "Up", DOWN: "Down", RGHT: "Right" }
  for (const [id, keysym] of Object.entries(keys))
    assert.deepStrictEqual(Typing.press(keymap, fresh(), id, 0).commands, [["wtype", "-k", keysym]])
})

test("Super and Alt latch too", () => {
  assert.deepStrictEqual(run(fresh(), ["LWIN", "LALT", "AD03"]).commands,
    [["wtype", "-M", "alt", "-M", "logo", "-k", "e", "-m", "logo", "-m", "alt"]])
})

test("function keys type their keysym", () => {
  assert.deepStrictEqual(run(fresh(), ["FK05"]).commands, [["wtype", "-k", "F5"]])
})

test("Backspace, Space and arrows repeat; letters do not", () => {
  assert.strictEqual(Typing.isRepeating("BKSP"), true)
  assert.strictEqual(Typing.isRepeating("LEFT"), true)
  assert.strictEqual(Typing.isRepeating("AD03"), false)
})

test("press-and-hold offers the accents for the current case", () => {
  assert.deepStrictEqual(Typing.accentsFor(keymap, "AD03", fresh()), ["è", "é", "ê", "ë"])
  assert.deepStrictEqual(Typing.accentsFor(keymap, "AE01", fresh()), [])
  const shifted = run(fresh(), ["LFSH"]).state
  assert.deepStrictEqual(Typing.accentsFor(keymap, "AD03", shifted), [])
})

test("choosing an accent types it and releases a latched Shift", () => {
  const shifted = run(fresh(), ["LFSH"]).state
  const result = Typing.choose(shifted, "é")
  assert.deepStrictEqual(result.commands, [["wtype", "--", "é"]])
  assert.strictEqual(result.state.shift, 0)
})

test("corner labels show the Shift symbol, but not for letter case pairs", () => {
  assert.strictEqual(Typing.alternateLabel(keymap, "AE01", fresh()), "!")
  assert.strictEqual(Typing.alternateLabel(keymap, "AD03", fresh()), "")
  const altgr = run(fresh(), ["RALT"]).state
  assert.strictEqual(Typing.alternateLabel(keymap, "AE01", altgr), "¡")
})

test("Shift hides corner labels while shortcut modifiers leave them visible", () => {
  assert.strictEqual(Typing.showsAlternates(fresh()), true)
  assert.strictEqual(Typing.showsAlternates(run(fresh(), ["LFSH"]).state), false)
  assert.strictEqual(Typing.showsAlternates(run(fresh(), ["LCTL"]).state), true)
})

test("Ctrl keeps the visible Shift, Caps and AltGr layers", () => {
  const state = run(fresh(), ["LFSH", "LCTL"]).state
  assert.strictEqual(Typing.label(keymap, "AD03", Typing.displayState(state)), "E")
  const caps = run(Typing.initialState(true), ["LCTL"]).state
  assert.strictEqual(Typing.label(keymap, "AD03", Typing.displayState(caps)), "E")
  const altgr = run(fresh(), ["RALT", "LCTL"]).state
  assert.strictEqual(Typing.label(keymap, "AD03", Typing.displayState(altgr)), "€")
})

test("Ctrl with AltGr sends the physical key chord, including on blank AltGr keys", () => {
  assert.deepStrictEqual(run(fresh(), ["LCTL", "RALT", "AD03"]).commands,
    [["wtype", "-M", "ctrl", "-M", "altgr", "-k", "e", "-m", "altgr", "-m", "ctrl"]])
  assert.deepStrictEqual(run(fresh(), ["LCTL", "RALT", "AB02"]).commands,
    [["wtype", "-M", "ctrl", "-M", "altgr", "-k", "x", "-m", "altgr", "-m", "ctrl"]])
})

test("AltGr combines with action keys", () => {
  assert.deepStrictEqual(run(fresh(), ["RALT", "TAB"]).commands,
    [["wtype", "-M", "altgr", "-k", "Tab", "-m", "altgr"]])
})

test("dead keys are recognised in the current layer", () => {
  assert.strictEqual(Typing.isDeadKey(keymap, "AC11", fresh()), true)
  assert.strictEqual(Typing.isDeadKey(keymap, "AC11", run(fresh(), ["RALT"]).state), false)
})

test("keys the layout does not define type nothing", () => {
  const altgr = run(fresh(), ["RALT"]).state
  assert.deepStrictEqual(Typing.press(keymap, altgr, "AB02", 0).commands, [])
  assert.deepStrictEqual(Typing.press(keymap, fresh(), "AB11", 0).commands, [])
})
