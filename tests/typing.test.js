const test = require("node:test")
const assert = require("node:assert")
const Typing = require("../Typing.js")

test("a dead acute key composes common Latin letters", () => {
  assert.strictEqual(Typing.compose("dead_acute", "e"), "é")
  assert.strictEqual(Typing.compose("dead_acute", "E"), "É")
})

test("dead keys can produce their spacing accent with Space", () => {
  assert.strictEqual(Typing.compose("dead_acute", " "), "´")
  assert.strictEqual(Typing.compose("dead_tilde", " "), "~")
})

test("unknown dead keys are left for the XKB fallback", () => {
  assert.strictEqual(Typing.compose("dead_hook", "e"), null)
})

test("long-press choices contain accented versions of a letter", () => {
  assert.deepStrictEqual(Typing.accents("e").slice(0, 4), ["é", "è", "ê", "ë"])
  assert.deepStrictEqual(Typing.accents("E").slice(0, 4), ["É", "È", "Ê", "Ë"])
  assert.deepStrictEqual(Typing.accents("1"), [])
})
