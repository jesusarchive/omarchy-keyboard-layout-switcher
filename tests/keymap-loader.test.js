const test = require("node:test")
const assert = require("node:assert/strict")
const qmlFunctions = require("./qml-functions.cjs")
const Typing = require("../Typing.js")

const us = { layout: "us", variant: "" }
const es = { layout: "es", variant: "" }
const fr = { layout: "fr", variant: "" }
const map = { keys: { AD01: { states: [{ keysym: "q", text: "q", label: "q", dead: "" }] } } }
const plain = value => JSON.parse(JSON.stringify(value))

function loader() {
  const deferred = []
  const state = qmlFunctions("KeymapLoader.qml", {
    active: true, layout: us, layouts: [us, es, fr], keyboardModel: "pc105", keyboardOptions: "",
    keymaps: {}, loadQueue: [], loadingSignature: "", failures: {},
    loadStreamDone: false, loadExited: false, scriptPath: "/plugin/keyboard_viewer.py",
    keymapProc: { running: false, command: [] }, streamTimeout: { stop() {} },
    Qt: { callLater(fn) { deferred.push(fn) } }
  })
  Object.defineProperty(state, "signature", { get: () => state.signatureFor(state.layout) })
  state.flush = () => { while (deferred.length) deferred.shift()() }
  state.exit = () => {
    state.keymapProc.running = false
    state.loadExited = true
    state.finishLoad()
  }
  return state
}

test("queued keymaps keep the model and options captured in their cache signature", () => {
  const state = loader()
  state.keyboardOptions = "compose:caps"
  state.load()
  const queued = plain(state.loadQueue[0])
  state.keyboardModel = "pc104"
  state.keyboardOptions = "lv3:ralt_switch"
  state.keymapRead(JSON.stringify(map))
  state.exit()
  state.flush()
  assert.equal(state.loadingSignature, queued.signature)
  assert.deepEqual(plain(state.keymapProc.command.slice(3)), ["es", "", "pc105", "compose:caps"])
})

for (const order of ["output first", "exit first"]) {
  test("loading waits for both output and exit, " + order, () => {
    const state = loader()
    state.load()
    const signature = state.loadingSignature
    if (order === "output first") state.keymapRead(JSON.stringify(map))
    else state.exit()
    state.flush()
    assert.equal(state.loadingSignature, signature)
    if (order === "output first") state.exit()
    else state.keymapRead(JSON.stringify(map))
    assert.deepEqual(plain(state.keymaps[signature]), map)
    assert.equal(state.loadingSignature, "")
    state.flush()
    assert.equal(state.keymapProc.command[3], "es")
  })
}

test("selecting a queued layout promotes it ahead of background loads", () => {
  const state = loader()
  state.load()
  state.layout = fr
  state.load()
  assert.deepEqual(plain(state.loadQueue.map(job => job.layout)), ["fr", "es"])
})

test("a completed old request is cached under its own signature after a layout change", () => {
  const state = loader()
  state.load()
  const original = state.loadingSignature
  state.layout = es
  state.keymapRead(JSON.stringify(map))
  state.exit()
  assert.deepEqual(plain(state.keymaps[original]), map)
  assert.equal(state.keymaps[state.signature], undefined)
})

test("cached keymaps and requests already in flight are not queued again", () => {
  const state = loader()
  state.keymaps[state.signatureFor(es)] = map
  state.load()
  state.load()
  assert.equal(state.loadingSignature, state.signature)
  assert.deepEqual(plain(state.loadQueue.map(job => job.layout)), ["fr"])
})

test("invalid output fails the request and permits a later retry", () => {
  for (const output of ["", "garbage", "null", "{}", '{"keys":[]}']) {
    const state = loader()
    state.layouts = [us]
    state.load()
    state.keymapRead(output)
    state.exit()
    assert.equal(state.keymaps[state.signature], undefined)
    assert.equal(state.failures[state.signature], true)
    state.flush()
    state.load()
    assert.equal(state.failures[state.signature], undefined)
    state.keymapRead(JSON.stringify(map))
    state.exit()
    assert.deepEqual(plain(state.keymaps[state.signature]), map)
  }
})

test("a background failure does not clear the active layout's error", () => {
  const state = loader()
  state.load()
  state.keymapRead("")
  state.exit()
  state.flush()
  state.keymapRead("")
  state.exit()
  assert.equal(state.failures[state.signatureFor(us)], true)
  assert.equal(state.failures[state.signatureFor(es)], true)
})

test("a closed viewer does not start new loads", () => {
  const state = loader()
  state.active = false
  state.load()
  assert.equal(state.keymapProc.running, false)
  assert.equal(state.loadQueue.length, 0)
})

test("viewer blocks letters, action keys and accents until the matching keymap is ready", () => {
  const commands = []
  const state = qmlFunctions("KeyboardViewer.qml", {
    Typing, keymapLoader: { ready: false }, keymap: map, typing: Typing.initialState(false),
    namedKeys: {}, closeAccents() {}, typeQueue: [], typeProc: { running: true }
  })
  state.queueType = command => commands.push(command)
  for (const id of ["AD01", "RTRN", "LFSH"]) {
    assert.equal(state.enabledFor(id), false)
    assert.equal(state.act(id).commands.length, 0)
  }
  state.chooseAccent("é")
  assert.equal(commands.length, 0)
  state.keymapLoader.ready = true
  state.act("AD01")
  assert.deepEqual(commands, [["wtype", "--", "q"]])
})
