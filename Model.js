// Layout parsing and switching logic, with no Qt imports.

// Hyprland lists virtual keyboards and ACPI buttons alongside physical keyboards.
// Exclude them from layout reads and switches.
var UNTYPED_KEYBOARDS = /^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus)/

function isTypedKeyboard(name) {
  return !UNTYPED_KEYBOARDS.test(String(name || ""))
}

// `xkbcli list` prints YAML blocks like:
//   - layout: 'es'
//     variant: ''
//     brief: 'es'
//     description: Spanish
// Returns { "es": {brief, description}, "es(nodeadkeys)": {...} }.
function layoutCatalog(text) {
  var catalog = {}
  var block = null

  function flush() {
    if (block && block.layout && block.description)
      catalog[catalogKey(block.layout, block.variant)] = { brief: block.brief || "", description: block.description }
    block = null
  }

  String(text || "").split("\n").forEach(function (line) {
    var start = line.match(/^- layout: '?([^']*)'?\s*$/)
    if (start) {
      flush()
      block = { layout: start[1], variant: "", brief: "", description: "" }
      return
    }
    if (/^\S/.test(line)) { flush(); return }
    if (!block) return
    var field = line.match(/^  (variant|brief|description): (.*)$/)
    if (field) block[field[1]] = field[2].replace(/^'|'$/g, "")
  })
  flush()
  return catalog
}

function catalogKey(layout, variant) {
  return variant ? layout + "(" + variant + ")" : layout
}

function splitList(value) {
  return String(value === undefined || value === null ? "" : value).split(",")
}

// Use xkb's brief language code: us becomes EN; es and latam both become ES.
// Fall back to the layout identifier when xkb has no brief code.
function shortCode(layout, variant, catalog) {
  var entry = (catalog || {})[catalogKey(layout, variant)] || (catalog || {})[layout]
  var code = entry && entry.brief ? entry.brief.split("-")[0] : String(layout || "").split("-")[0]
  return code.substring(0, 3).toUpperCase()
}

// The badge fits at most two letters.
function iconGlyph(layout) {
  if (!layout) return ""
  return layout.code.length > 2 ? layout.code.substring(0, 2) : layout.code
}

function layoutName(layout, variant, catalog) {
  var entry = (catalog || {})[catalogKey(layout, variant)] || (catalog || {})[layout]
  if (entry && entry.description) return entry.description
  return variant ? layout + " (" + variant + ")" : layout
}

// Give layouts with the same code distinct labels. Try letters from the variant,
// then the layout's position: us and us(intl) become EN and ENI.
function disambiguate(list) {
  var taken = {}
  list.forEach(function (layout) {
    if (!taken[layout.code]) {
      taken[layout.code] = true
      return
    }
    var stem = layout.code.substring(0, 2)
    var tries = []
    for (var i = 0; i < layout.variant.length; i++) tries.push(stem + layout.variant.charAt(i).toUpperCase())
    tries.push(stem + String(layout.index + 1))
    for (var t = 0; t < tries.length; t++) {
      if (!taken[tries[t]]) {
        layout.code = tries[t]
        break
      }
    }
    taken[layout.code] = true
  })
}

// Keyboard layouts in kb_layout order.
function layouts(keyboard, catalog) {
  if (!keyboard || !keyboard.layout) return []
  var layouts = splitList(keyboard.layout)
  var variants = splitList(keyboard.variant)
  var out = []
  for (var i = 0; i < layouts.length; i++) {
    var layout = layouts[i].trim()
    if (!layout) continue
    var variant = (variants[i] || "").trim()
    out.push({
      index: i,
      layout: layout,
      variant: variant,
      code: shortCode(layout, variant, catalog),
      name: layoutName(layout, variant, catalog)
    })
  }
  disambiguate(out)
  out.forEach(function (layout) { layout.glyph = iconGlyph(layout) })
  return out
}

// Prefer the last device named by an activelayout event, then Hyprland's main
// keyboard. The highest active index is a fallback when neither is available.
function selectKeyboard(typed, namedByEvent) {
  var keyboards = typed || []
  if (keyboards.length === 0) return null
  return keyboards.find(function (k) { return k.name === namedByEvent })
    || keyboards.find(function (k) { return k.main === true })
    || keyboards.reduce(function (best, k) {
      return (k.active_layout_index || 0) > (best.active_layout_index || 0) ? k : best
    }, keyboards[0])
}

// Everything the service needs from one `hyprctl -j devices` reading.
function readDevices(json, catalog, namedByEvent) {
  var parsed
  try {
    parsed = typeof json === "string" ? JSON.parse(json || "{}") : json
  } catch (e) {
    return null
  }
  if (!parsed || !Array.isArray(parsed.keyboards)) return null
  var typed = parsed.keyboards.filter(function (k) { return isTypedKeyboard(k.name) })
  var keyboard = selectKeyboard(typed, namedByEvent)
  return {
    keyboards: typed.map(function (k) { return String(k.name) }),
    layouts: layouts(keyboard, catalog),
    activeIndex: keyboard ? (keyboard.active_layout_index || 0) : 0,
    keyboardModel: keyboard ? String(keyboard.model || "") : "",
    keyboardOptions: keyboard ? String(keyboard.options || "") : "",
    capsLock: typed.some(function (k) { return k.capsLock === true })
  }
}

// The activelayout event is "keyboard,description"; a description can carry
// its own comma, so only split once.
function eventKeyboardName(data) {
  var name = eventDevice(data)
  return isVirtualKeyboard(name) ? "" : name
}

// Virtual keyboards (fcitx5, and wtype on every keyboard viewer click) send
// activelayout events of their own. They never change the typed layout.
function isVirtualKeyboardEvent(data) {
  return isVirtualKeyboard(eventDevice(data))
}

function eventDevice(data) {
  var text = String(data || "")
  var comma = text.indexOf(",")
  return comma === -1 ? text : text.substring(0, comma)
}

function isVirtualKeyboard(name) {
  return name.indexOf("hl-virtual-keyboard") === 0
}

// Returns the most-recently-used order, newest first, dropping any index
// that no longer exists.
function touchRecent(recent, index, count) {
  var next = [index]
  ;(recent || []).forEach(function (i) {
    if (i !== index && i >= 0 && i < count && next.indexOf(i) === -1) next.push(i)
  })
  return next
}

// Ctrl+Space goes to the layout used before the current one.
function previousIndex(recent, active, count) {
  if (count <= 1) return active
  var list = recent || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] !== active && list[i] >= 0 && list[i] < count) return list[i]
  }
  return nextIndex(active, count)
}

// Steps to the next layout in order.
function nextIndex(active, count) {
  if (count <= 1) return active
  return ((active || 0) + 1) % count
}

// `set` accepts an index, a code (ES) or a layout (es, us(intl)).
function resolveLayout(layoutList, query) {
  var q = String(query === undefined || query === null ? "" : query).trim()
  if (!q) return -1
  var list = layoutList || []
  if (/^\d+$/.test(q)) {
    var n = parseInt(q, 10)
    return n >= 0 && n < list.length ? n : -1
  }
  var lower = q.toLowerCase()
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (s.code.toLowerCase() === lower || catalogKey(s.layout, s.variant).toLowerCase() === lower) return i
  }
  for (var j = 0; j < list.length; j++) {
    if (list[j].layout.toLowerCase() === lower) return j
  }
  return -1
}

// Run one command per typed keyboard. hyprctl --batch splits on semicolons
// without shell quoting, so passing a device name through it would be unsafe.
function switchCommands(keyboards, index) {
  return (keyboards || []).map(function (name) {
    return ["hyprctl", "switchxkblayout", String(name), String(index)]
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    isTypedKeyboard: isTypedKeyboard,
    layoutCatalog: layoutCatalog,
    shortCode: shortCode,
    iconGlyph: iconGlyph,
    layouts: layouts,
    selectKeyboard: selectKeyboard,
    readDevices: readDevices,
    eventKeyboardName: eventKeyboardName,
    isVirtualKeyboardEvent: isVirtualKeyboardEvent,
    touchRecent: touchRecent,
    previousIndex: previousIndex,
    nextIndex: nextIndex,
    resolveLayout: resolveLayout,
    switchCommands: switchCommands
  }
}
