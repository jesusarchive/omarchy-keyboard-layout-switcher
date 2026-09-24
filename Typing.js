// What a click on the keyboard viewer types, with no Qt imports.
//
// The viewer keeps its own modifier and dead-key state, because every wtype
// process is a separate keyboard device: a modifier pressed by one process is
// not held for the next. Each click therefore becomes one self-contained wtype
// command. Characters come from the keymap that keyboard_viewer.py prints.

// Modifiers are 0 (off), 1 (latched for the next key) or 2 (locked).
var LATCHED = 1
var LOCKED = 2
// A second click this soon after latching a modifier locks it.
var LOCK_CLICK_MS = 400

var SPECIAL_KEYS = {
  ESC: "Escape", BKSP: "BackSpace", TAB: "Tab", RTRN: "Return", SPCE: "space",
  LEFT: "Left", UP: "Up", DOWN: "Down", RGHT: "Right"
}

// Keys that repeat while held, like a physical keyboard.
var REPEATING = { BKSP: true, SPCE: true, LEFT: true, UP: true, DOWN: true, RGHT: true }

// wtype modifier names, in the order they are pressed.
var CHORD_ORDER = ["ctrl", "alt", "logo", "altgr", "shift"]

function initialState(capsLock) {
  return { shift: 0, altgr: 0, ctrl: 0, alt: 0, logo: 0, caps: !!capsLock, dead: "", deadId: "", latchedName: "", latchedAt: 0 }
}

function copy(state) {
  var next = {}
  for (var key in state) next[key] = state[key]
  return next
}

function specialKeysym(id) {
  if (SPECIAL_KEYS[id]) return SPECIAL_KEYS[id]
  var fn = /^FK(\d\d)$/.exec(id)
  return fn ? "F" + parseInt(fn[1], 10) : ""
}

function isRepeating(id) { return REPEATING[id] === true }

// The viewer state a key represents, or "" for other keys. Right Alt is AltGr
// only when the layout has a third level.
function modifierFor(id, keymap) {
  if (id === "LFSH" || id === "RTSH") return "shift"
  if (id === "LCTL") return "ctrl"
  if (id === "LALT") return "alt"
  if (id === "LWIN") return "logo"
  if (id === "RALT") return hasAltGr(keymap) ? "altgr" : "alt"
  return ""
}

function hasAltGr(keymap) { return !!(keymap && keymap.altGrKey === "RALT") }

function stateIndex(state) {
  return (state.shift ? 1 : 0) + (state.caps ? 2 : 0) + (state.altgr ? 4 : 0)
}

function entry(keymap, id, state) {
  var key = keymap && keymap.keys ? keymap.keys[id] : null
  return key ? key.states[stateIndex(state)] || null : null
}

// Shortcuts hold Ctrl, Alt or Super. Shift and AltGr alone only pick a symbol.
function isChord(state) { return !!(state.ctrl || state.alt || state.logo) }

function chordModifiers(state) {
  return CHORD_ORDER.filter(function (name) { return state[name] })
}

function chordCommand(modifiers, keysym) {
  var command = ["wtype"]
  modifiers.forEach(function (name) { command.push("-M", name) })
  command.push("-k", keysym)
  modifiers.slice().reverse().forEach(function (name) { command.push("-m", name) })
  return command
}

function typeText(text) { return ["wtype", "--", text] }

function releaseLatched(state) {
  var next = copy(state)
  ;["shift", "altgr", "ctrl", "alt", "logo"].forEach(function (name) {
    if (next[name] === LATCHED) next[name] = 0
  })
  return next
}

function clearDead(state) {
  var next = copy(state)
  next.dead = ""
  next.deadId = ""
  return next
}

function composed(keymap, dead, keysym) {
  var table = keymap && keymap.compose ? keymap.compose[dead] : null
  return table && table[keysym] ? table[keysym] : ""
}

// What a dead key types on its own when Compose has no dead key + Space entry.
var SPACING_FALLBACK = {
  dead_acute: "´", dead_grave: "`", dead_circumflex: "^", dead_tilde: "~",
  dead_diaeresis: "¨", dead_cedilla: "¸", dead_caron: "ˇ", dead_breve: "˘",
  dead_abovering: "˚", dead_macron: "¯", dead_doubleacute: "˝", dead_ogonek: "˛",
  dead_abovedot: "˙"
}

function spacing(keymap, dead) {
  return composed(keymap, dead, "space") || SPACING_FALLBACK[dead] || ""
}

function toggleModifier(state, name, now) {
  var next = copy(state)
  if (!state[name]) {
    next[name] = LATCHED
    next.latchedName = name
    next.latchedAt = now
  } else if (state[name] === LATCHED && state.latchedName === name && now - state.latchedAt < LOCK_CLICK_MS) {
    next[name] = LOCKED
  } else {
    next[name] = 0
  }
  return next
}

// Returns { state, commands } for one click on key `id`.
function press(keymap, state, id, now) {
  var modifier = modifierFor(id, keymap)
  if (modifier) return { state: toggleModifier(state, modifier, now || 0), commands: [] }

  // The viewer's Caps Lock only picks which symbols it types, so it works
  // even when the physical key is remapped (for example compose:caps).
  if (id === "CAPS") {
    var capsState = copy(state)
    capsState.caps = !state.caps
    return { state: capsState, commands: [] }
  }

  var commands = []
  var special = specialKeysym(id)
  if (special) {
    if (state.dead) {
      // Esc and Backspace cancel a pending accent; other keys type it first.
      if (id === "ESC" || id === "BKSP")
        return { state: clearDead(state), commands: [] }
      var accent = spacing(keymap, state.dead)
      if (accent) commands.push(typeText(accent))
      if (id === "SPCE") return { state: releaseLatched(clearDead(state)), commands: commands }
    }
    var modifiers = chordModifiers(state)
    commands.push(modifiers.length ? chordCommand(modifiers, special) : ["wtype", "-k", special])
    return { state: releaseLatched(clearDead(state)), commands: commands }
  }

  if (isChord(state)) {
    // Shortcuts use the physical base key plus held modifiers. This also
    // works when that key has no symbol on the Shift or AltGr layer.
    var base = entry(keymap, id, { shift: 0, caps: false, altgr: 0 })
    if (!base || !base.keysym) return { state: state, commands: [] }
    commands.push(chordCommand(chordModifiers(state), base.keysym))
    return { state: releaseLatched(clearDead(state)), commands: commands }
  }

  var current = entry(keymap, id, state)
  if (!current || !current.keysym) return { state: state, commands: [] }

  if (current.dead) {
    var next = releaseLatched(state)
    if (state.dead) {
      // Two dead keys can compose (´ ´ gives ´). Otherwise the first one is
      // typed on its own and the second one waits.
      var both = composed(keymap, state.dead, current.keysym)
      if (both) {
        commands.push(typeText(both))
        return { state: clearDead(next), commands: commands }
      }
      var previous = spacing(keymap, state.dead)
      if (previous) commands.push(typeText(previous))
    }
    next.dead = current.dead
    next.deadId = id
    return { state: next, commands: commands }
  }

  if (state.dead) {
    // An accent with no composed form types the accent, then the character,
    // as macOS does.
    commands.push(typeText(composed(keymap, state.dead, current.keysym)
      || spacing(keymap, state.dead) + current.text))
  } else if (current.text) {
    commands.push(typeText(current.text))
  } else {
    commands.push(["wtype", "-k", current.keysym])
  }
  return { state: releaseLatched(clearDead(state)), commands: commands }
}

// Super uses the physical base key for shortcuts, so show that key on the
// viewer. Ctrl keeps the visible layer, as macOS's Keyboard Viewer does.
function displayState(state) {
  if (!state.logo) return state
  var shown = copy(state)
  shown.shift = 0
  shown.caps = false
  shown.altgr = 0
  return shown
}

// Corner labels show the Shift symbol on the base and AltGr layers only.
function showsAlternates(state) { return !state.shift && !state.logo }

// Press-and-hold choices for a key in the current state.
function accentsFor(keymap, id, state) {
  if (isChord(state) || state.dead) return []
  var current = entry(keymap, id, state)
  if (!current || !current.text || !keymap.accents) return []
  return keymap.accents[current.text] || []
}

function choose(state, text) {
  return { state: releaseLatched(clearDead(state)), commands: [typeText(text)] }
}

// Key face text. Named keys come from the viewer; this covers layout keys.
function label(keymap, id, state) {
  var current = entry(keymap, id, state)
  return current ? current.label : ""
}

// The symbol shown small in the corner: the other Shift level, when the two
// are not just upper and lower case of one letter.
function alternateLabel(keymap, id, state) {
  var current = entry(keymap, id, state)
  var flipped = copy(state)
  flipped.shift = state.shift ? 0 : LATCHED
  var other = entry(keymap, id, flipped)
  if (!current || !other || !other.label || other.label === current.label) return ""
  var a = current.label, b = other.label
  if (a.toUpperCase() === b.toUpperCase() && a.toLowerCase() !== a.toUpperCase()) return ""
  return b
}

function isDeadKey(keymap, id, state) {
  var current = entry(keymap, id, state)
  return !!(current && current.dead)
}

if (typeof module !== "undefined") {
  module.exports = {
    LATCHED: LATCHED, LOCKED: LOCKED, LOCK_CLICK_MS: LOCK_CLICK_MS,
    initialState: initialState, specialKeysym: specialKeysym, isRepeating: isRepeating,
    modifierFor: modifierFor, hasAltGr: hasAltGr, isChord: isChord,
    stateIndex: stateIndex, entry: entry, press: press, accentsFor: accentsFor, choose: choose,
    displayState: displayState, showsAlternates: showsAlternates,
    label: label, alternateLabel: alternateLabel, isDeadKey: isDeadKey, spacing: spacing
  }
}
