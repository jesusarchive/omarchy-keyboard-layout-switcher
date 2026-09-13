// Pure logic for the language switcher, kept Qt-free so node can test it.

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

// Short label for a source: xkb's language code (us → EN, es → ES, latam →
// ES), falling back to the layout name when xkb has no brief for it.
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
  // Two sources sharing a code (us and us(intl)) get a variant hint so the
  // badges can be told apart.
  out.forEach(function (source) {
    var clash = out.some(function (other) { return other !== source && other.code === source.code })
    if (clash && source.variant) source.code = source.code.substring(0, 2) + source.variant.charAt(0).toUpperCase()
  })
  out.forEach(function (source) { source.glyph = iconGlyph(source) })
  return out
}

// The keyboard being typed on: the one the last activelayout event named, or
// failing that the furthest-advanced one.
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

// Most-recently-used order, newest first, limited to indices that exist.
function touchRecent(recent, index, count) {
  var next = [index]
  ;(recent || []).forEach(function (i) {
    if (i !== index && i >= 0 && i < count && next.indexOf(i) === -1) next.push(i)
  })
  return next
}

// Control-Space: the source used before the current one.
function previousIndex(recent, active, count) {
  if (count <= 1) return active
  var list = recent || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] !== active && list[i] >= 0 && list[i] < count) return list[i]
  }
  return nextIndex(active, count)
}

// Control-Option-Space: the next source in order.
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

// hyprctl batch that moves every typed keyboard to one layout, so a second
// keyboard doesn't stay on the old source.
function switchBatch(keyboards, index) {
  return (keyboards || []).map(function (name) {
    return "switchxkblayout " + name + " " + index
  }).join(" ; ")
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
    switchBatch: switchBatch
  }
}
