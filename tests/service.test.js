const test = require("node:test")
const assert = require("node:assert/strict")
const qmlFunctions = require("./qml-functions.cjs")
const Model = require("../Model.js")

function service() {
  const commands = []
  let guards = 0
  const state = qmlFunctions("Service.qml", {
    Model, layouts: Model.layouts({ layout: "us,es,fr" }, {}),
    keyboards: ["main", "new-keyboard"], activeIndex: 1, recent: [1, 0], _switcherOrigin: -1,
    Quickshell: { execDetached(command) { commands.push(command) } },
    switchGuard: { restart() { guards++ } }
  })
  return { state, commands, guards: () => guards }
}

test("selecting the current layout also synchronizes a newly connected keyboard", () => {
  const { state, commands, guards } = service()
  assert.equal(state.select(1), true)
  assert.deepEqual(commands, [
    ["hyprctl", "switchxkblayout", "main", "1"],
    ["hyprctl", "switchxkblayout", "new-keyboard", "1"]
  ])
  assert.deepEqual(state.recent, [1, 0])
  assert.equal(guards(), 1)
})

test("switching does not update history until the switcher commits", () => {
  const { state } = service()
  state._switcherOrigin = state.activeIndex
  state.switchTo(0)
  state.switchTo(2)
  assert.deepEqual(state.recent, [1, 0])
  state.commitSwitcher()
  assert.deepEqual(state.recent, [2, 1, 0])
  assert.equal(state._switcherOrigin, -1)
})

test("direct selection still updates the recent layout order", () => {
  const { state } = service()
  assert.equal(state.select(2), true)
  assert.equal(state.activeIndex, 2)
  assert.deepEqual(state.recent, [2, 1, 0])
})

test("invalid selections and a missing keyboard issue no commands or history changes", () => {
  const { state, commands, guards } = service()
  assert.equal(state.select(-1), false)
  assert.equal(state.select(3), false)
  state.keyboards = []
  assert.equal(state.select(0), false)
  assert.deepEqual(commands, [])
  assert.deepEqual(state.recent, [1, 0])
  assert.equal(state.activeIndex, 1)
  assert.equal(guards(), 0)
})
