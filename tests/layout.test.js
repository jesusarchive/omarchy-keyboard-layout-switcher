const test = require("node:test")
const assert = require("node:assert")
const ViewerLayout = require("../ViewerLayout.js")

const names = Object.keys(ViewerLayout.GEOMETRIES)
const pitch = 50
const gap = 4

function ids(placed) { return placed.keys.map(k => k.id) }

// Absolute rectangles a key covers, so the L-shaped Enter counts as two.
function areas(placed) {
  return placed.keys.flatMap(k => k.rects.map(r => ({ id: k.id, x: k.x + r.x, y: k.y + r.y, w: r.w, h: r.h })))
}

test("every row of every geometry is 15 units wide", () => {
  for (const name of names) {
    ViewerLayout.GEOMETRIES[name].forEach((row, index) => {
      assert.strictEqual(ViewerLayout.rowUnits(row), ViewerLayout.ROW_UNITS, `${name} row ${index}`)
    })
  }
})

test("auto picks the physical keyboard from the layout and model", () => {
  assert.strictEqual(ViewerLayout.geometryFor("auto", "us", ""), "ansi")
  assert.strictEqual(ViewerLayout.geometryFor("auto", "es", ""), "iso")
  assert.strictEqual(ViewerLayout.geometryFor("auto", "de", "pc105"), "iso")
  assert.strictEqual(ViewerLayout.geometryFor("auto", "de", "pc104"), "ansi")
  assert.strictEqual(ViewerLayout.geometryFor("auto", "br", ""), "abnt")
  assert.strictEqual(ViewerLayout.geometryFor("auto", "jp", ""), "jis")
})

test("an explicit setting wins over auto, and nonsense falls back to auto", () => {
  assert.strictEqual(ViewerLayout.geometryFor("iso", "us", ""), "iso")
  assert.strictEqual(ViewerLayout.geometryFor("ansi", "es", ""), "ansi")
  assert.strictEqual(ViewerLayout.geometryFor("qwertz", "us", ""), "ansi")
})

test("ANSI has no ISO key; ISO has it and keeps Backslash beside Enter", () => {
  assert.ok(!ids(ViewerLayout.place("ansi", pitch, gap)).includes("LSGT"))
  const iso = ViewerLayout.place("iso", pitch, gap)
  assert.ok(ids(iso).includes("LSGT"))
  const bksl = iso.keys.find(k => k.id === "BKSL")
  const ac11 = iso.keys.find(k => k.id === "AC11")
  assert.strictEqual(bksl.y, ac11.y)
})

test("ABNT and JIS add their extra keys", () => {
  assert.ok(ids(ViewerLayout.place("abnt", pitch, gap)).includes("AB11"))
  const jis = ids(ViewerLayout.place("jis", pitch, gap))
  assert.ok(jis.includes("AE13"))
  assert.ok(jis.includes("AB11"))
})

test("the ISO Enter is one L-shaped key spanning two rows", () => {
  const iso = ViewerLayout.place("iso", pitch, gap)
  const enters = iso.keys.filter(k => k.id === "RTRN")
  assert.strictEqual(enters.length, 1)
  const enter = enters[0]
  assert.strictEqual(enter.rects.length, 2)
  assert.ok(enter.cutW > 0)
  assert.strictEqual(enter.cutY, pitch - gap)
  assert.strictEqual(enter.h, 2 * pitch - gap)
  assert.strictEqual(enter.x + enter.w, iso.width)
})

test("ANSI Enter is a plain one-row key", () => {
  const enter = ViewerLayout.place("ansi", pitch, gap).keys.find(k => k.id === "RTRN")
  assert.strictEqual(enter.cutW, 0)
  assert.strictEqual(enter.rects.length, 1)
})

test("arrows form an inverted T of half-height keys", () => {
  const keys = ViewerLayout.place("ansi", pitch, gap).keys
  const [left, up, down, right] = ["LEFT", "UP", "DOWN", "RGHT"].map(id => keys.find(k => k.id === id))
  assert.strictEqual(left.y, down.y)
  assert.strictEqual(right.y, down.y)
  assert.strictEqual(up.x, down.x)
  assert.ok(up.y < down.y)
  assert.strictEqual(up.h, down.h)
  assert.strictEqual(up.y + up.h + gap, down.y)
})

test("keys fit the keyboard and never overlap", () => {
  for (const name of names) {
    const placed = ViewerLayout.place(name, pitch, gap)
    const rects = areas(placed)
    for (const r of rects) {
      assert.ok(r.x >= 0 && r.y >= 0, `${name} ${r.id} starts inside`)
      assert.ok(r.x + r.w <= placed.width + 1e-9 && r.y + r.h <= placed.height + 1e-9, `${name} ${r.id} ends inside`)
    }
    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i], b = rects[j]
        if (a.id === b.id) continue
        const overlap = a.x < b.x + b.w - 1e-9 && b.x < a.x + a.w - 1e-9 && a.y < b.y + b.h - 1e-9 && b.y < a.y + a.h - 1e-9
        assert.ok(!overlap, `${name}: ${a.id} overlaps ${b.id}`)
      }
    }
  }
})

test("both edges of every full row line up", () => {
  const placed = ViewerLayout.place("iso", pitch, gap)
  const rows = new Map()
  for (const k of placed.keys) {
    if (["UP", "DOWN", "LEFT", "RGHT"].includes(k.id)) continue
    const row = rows.get(k.y) || []
    row.push(k)
    rows.set(k.y, row)
  }
  for (const row of rows.values()) {
    assert.strictEqual(Math.min(...row.map(k => k.x)), 0)
  }
})
