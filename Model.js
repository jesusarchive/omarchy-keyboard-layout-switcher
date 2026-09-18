// Pure logic for the language switcher, with no Qt imports so node can test it.

// Devices Hyprland reports as keyboards that nobody types on: fcitx5's virtual
// keyboard and the ACPI buttons. They carry the layout list too, so reading or
// switching them would describe a button instead of the keyboard.
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

// The short label for a source is xkb's language code, so us becomes EN, and
// both es and latam become ES. A layout xkb has no brief for keeps its own name.
function shortCode(layout, variant, catalog) {
  var entry = (catalog || {})[catalogKey(layout, variant)] || (catalog || {})[layout]
  var code = entry && entry.brief ? entry.brief.split("-")[0] : String(layout || "").split("-")[0]
  return code.substring(0, 3).toUpperCase()
}

// The letters drawn inside the source icon.
function iconGlyph(source) {
  if (!source) return ""
  return source.code.length > 2 ? source.code.substring(0, 2) : source.code
}

function sourceName(layout, variant, catalog) {
  var entry = (catalog || {})[catalogKey(layout, variant)] || (catalog || {})[layout]
  if (entry && entry.description) return entry.description
  return variant ? layout + " (" + variant + ")" : layout
}

// Two badges must never read the same. A source whose code another source
// already holds takes a variant letter instead, so us and us(intl) become EN
// and ENI. If another source holds that letter too, this tries the rest of the
// variant, then the source's position in the list. This walks the list in order and
// records every code it hands out, so rewriting one source can never produce a
// code that another source already has.
function disambiguate(list) {
  var taken = {}
  list.forEach(function (source) {
    if (!taken[source.code]) {
      taken[source.code] = true
      return
    }
    var stem = source.code.substring(0, 2)
    var tries = []
    for (var i = 0; i < source.variant.length; i++) tries.push(stem + source.variant.charAt(i).toUpperCase())
    tries.push(stem + String(source.index + 1))
    for (var t = 0; t < tries.length; t++) {
      if (!taken[tries[t]]) {
        source.code = tries[t]
        break
      }
    }
    taken[source.code] = true
  })
}

// Input sources in kb_layout order.
function sources(keyboard, catalog) {
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
      name: sourceName(layout, variant, catalog)
    })
  }
  disambiguate(out)
  out.forEach(function (source) { source.glyph = iconGlyph(source) })
  return out
}

// Picks the keyboard being typed on. That is the one the last activelayout
// event named, or the furthest-advanced one when no event has named any.
function selectKeyboard(typed, namedByEvent) {
  var keyboards = typed || []
  if (keyboards.length === 0) return null
  return keyboards.find(function (k) { return k.name === namedByEvent }) || keyboards.reduce(function (best, k) {
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
    sources: sources(keyboard, catalog),
    activeIndex: keyboard ? (keyboard.active_layout_index || 0) : 0,
    capsLock: typed.some(function (k) { return k.capsLock === true })
  }
}

// The activelayout event is "keyboard,description"; a description can carry
// its own comma, so only split once.
function eventKeyboardName(data) {
  var text = String(data || "")
  var comma = text.indexOf(",")
  var name = comma === -1 ? text : text.substring(0, comma)
  return name.indexOf("hl-virtual-keyboard") === 0 ? "" : name
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

// Ctrl+Space goes to the source used before the current one.
function previousIndex(recent, active, count) {
  if (count <= 1) return active
  var list = recent || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] !== active && list[i] >= 0 && list[i] < count) return list[i]
  }
  return nextIndex(active, count)
}

// Ctrl+Alt+Space goes to the next source in order.
function nextIndex(active, count) {
  if (count <= 1) return active
  return ((active || 0) + 1) % count
}

// `set` accepts an index, a code (ES) or a layout (es, us(intl)).
function resolveSource(sourceList, query) {
  var q = String(query === undefined || query === null ? "" : query).trim()
  if (!q) return -1
  var list = sourceList || []
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

// One hyprctl argv per typed keyboard, so a second keyboard doesn't stay on the
// old source. These are separate argv vectors rather than one `hyprctl --batch`
// string. Batch splits its argument on ";" and has no quoting, so a device name
// that held a semicolon or a space would run as a command of its own.
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
    sources: sources,
    selectKeyboard: selectKeyboard,
    readDevices: readDevices,
    eventKeyboardName: eventKeyboardName,
    touchRecent: touchRecent,
    previousIndex: previousIndex,
    nextIndex: nextIndex,
    resolveSource: resolveSource,
    switchCommands: switchCommands
  }
}
