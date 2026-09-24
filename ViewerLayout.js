// Physical key geometry for the keyboard viewer, with no Qt imports.
//
// Rows are measured in key units and every row is 15 units wide, so both edges
// line up. A key that appears in two rows (the ISO Enter) becomes one L-shaped
// key. ARROWS expands into an inverted T of half-height keys.

var ROWS = 15

function k(id, units) { return { id: id, units: units || 1 } }

function ids(list) { return list.split(" ").map(function (id) { return k(id) }) }

var FUNCTION_ROW = [k("ESC", 1.5)].concat(
  "FK01 FK02 FK03 FK04 FK05 FK06 FK07 FK08 FK09 FK10 FK11 FK12".split(" ").map(function (id) { return k(id, 1.125) }))
var DIGITS = ids("TLDE AE01 AE02 AE03 AE04 AE05 AE06 AE07 AE08 AE09 AE10 AE11 AE12")
var TOP = ids("AD01 AD02 AD03 AD04 AD05 AD06 AD07 AD08 AD09 AD10 AD11 AD12")
var HOME = ids("AC01 AC02 AC03 AC04 AC05 AC06 AC07 AC08 AC09 AC10 AC11")
var BOTTOM = ids("AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10")
var SPACE_ROW = [k("LCTL", 1.25), k("LWIN", 1.25), k("LALT", 1.25), k("SPCE", 7), k("RALT", 1.25), k("ARROWS", 3)]

// Row heights in units. The function row is shorter, as on most laptops.
var FUNCTION_HEIGHT = 0.75

var GEOMETRIES = {
  ansi: [
    FUNCTION_ROW,
    DIGITS.concat([k("BKSP", 2)]),
    [k("TAB", 1.5)].concat(TOP, [k("BKSL", 1.5)]),
    [k("CAPS", 1.75)].concat(HOME, [k("RTRN", 2.25)]),
    [k("LFSH", 2.25)].concat(BOTTOM, [k("RTSH", 2.75)]),
    SPACE_ROW
  ],
  iso: [
    FUNCTION_ROW,
    DIGITS.concat([k("BKSP", 2)]),
    [k("TAB", 1.5)].concat(TOP, [k("RTRN", 1.5)]),
    [k("CAPS", 1.75)].concat(HOME, [k("BKSL"), k("RTRN", 1.25)]),
    [k("LFSH", 1.25), k("LSGT")].concat(BOTTOM, [k("RTSH", 2.75)]),
    SPACE_ROW
  ],
  // Brazilian ABNT2 adds a key between the period row's last key and Shift.
  abnt: [
    FUNCTION_ROW,
    DIGITS.concat([k("BKSP", 2)]),
    [k("TAB", 1.5)].concat(TOP, [k("RTRN", 1.5)]),
    [k("CAPS", 1.75)].concat(HOME, [k("BKSL"), k("RTRN", 1.25)]),
    [k("LFSH", 1.25), k("LSGT")].concat(BOTTOM, [k("AB11"), k("RTSH", 1.75)]),
    SPACE_ROW
  ],
  // Japanese JIS adds the yen key to the digit row and the ro key by Shift.
  jis: [
    FUNCTION_ROW,
    DIGITS.concat([k("AE13"), k("BKSP")]),
    [k("TAB", 1.5)].concat(TOP, [k("RTRN", 1.5)]),
    [k("CAPS", 1.75)].concat(HOME, [k("BKSL"), k("RTRN", 1.25)]),
    [k("LFSH", 2.25)].concat(BOTTOM, [k("AB11"), k("RTSH", 1.75)]),
    SPACE_ROW
  ]
}

// Pick the physical keyboard to draw. An explicit setting wins; otherwise
// Japanese and Brazilian layouts get their own boards, US layouts and pc104
// keyboards get ANSI, and everything else gets ISO.
function geometryFor(setting, layout, model) {
  if (GEOMETRIES[setting]) return setting
  if (layout === "jp") return "jis"
  if (layout === "br") return "abnt"
  if (layout === "us" || /(^|[^0-9])104/.test(String(model || ""))) return "ansi"
  return "iso"
}

function rowUnits(row) {
  return row.reduce(function (total, key) { return total + key.units }, 0)
}

// Positions in pixels. pitch is the width of one unit including the gap, so a
// key of n units is n * pitch - gap wide.
function place(name, pitch, gap) {
  var rows = GEOMETRIES[name] || GEOMETRIES.iso
  var keys = []
  var byId = {}
  var y = 0
  rows.forEach(function (row, rowIndex) {
    var height = (rowIndex === 0 ? FUNCTION_HEIGHT : 1) * pitch - gap
    var x = 0
    row.forEach(function (spec) {
      var w = spec.units * pitch - gap
      if (spec.id === "ARROWS") {
        arrows(x, y, pitch, height, gap).forEach(function (key) { keys.push(key) })
      } else if (byId[spec.id]) {
        joinBelow(byId[spec.id], x, y, w, height)
      } else {
        var key = { id: spec.id, x: x, y: y, w: w, h: height, cutW: 0, cutY: 0,
          rects: [{ x: 0, y: 0, w: w, h: height }] }
        byId[spec.id] = key
        keys.push(key)
      }
      x += spec.units * pitch
    })
    y += height + gap
  })
  return { keys: keys, width: ROWS * pitch - gap, height: y - gap }
}

// Grow a key down into the next row as an L: the top part keeps its width and
// the lower part is the narrower slot at the right. cutW and cutY describe the
// empty notch at the bottom left.
function joinBelow(key, x, y, w, h) {
  var right = key.x + key.w
  var topHeight = key.h
  key.h = y + h - key.y
  key.cutW = x - key.x
  key.cutY = topHeight
  key.rects = [
    { x: 0, y: 0, w: key.w, h: topHeight },
    { x: key.cutW, y: 0, w: right - x, h: key.h }
  ]
}

// Left, Down and Right sit on the bottom half; Up sits above Down.
function arrows(x, y, pitch, height, gap) {
  var half = (height - gap) / 2
  var w = pitch - gap
  function key(id, dx, top) {
    return { id: id, x: x + dx * pitch, y: top ? y : y + half + gap, w: w, h: half, cutW: 0, cutY: 0,
      rects: [{ x: 0, y: 0, w: w, h: half }] }
  }
  return [key("LEFT", 0, false), key("UP", 1, true), key("DOWN", 1, false), key("RGHT", 2, false)]
}

if (typeof module !== "undefined") {
  module.exports = { GEOMETRIES: GEOMETRIES, ROWS: ROWS, geometryFor: geometryFor, rowUnits: rowUnits, place: place }
}
