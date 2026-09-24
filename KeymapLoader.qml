import QtQuick
import Quickshell.Io

// Owns keymap requests and their cache. Each job captures all compiler inputs.
Item {
  id: root

  property bool active: false
  property var layout: null
  property var layouts: []
  property string keyboardModel: ""
  property string keyboardOptions: ""

  readonly property string signature: signatureFor(layout)
  // Never expose a previous layout while the current one is loading or failed.
  readonly property var keymap: keymaps[signature] || null
  readonly property bool ready: keymap !== null
  readonly property string errorText: failures[signature]
    ? "Could not read this keyboard layout" : ""
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("keyboard_viewer.py")).replace(/^file:\/\//, ""))

  property var keymaps: ({})
  property var loadQueue: []
  property string loadingSignature: ""
  property var failures: ({})
  property bool loadStreamDone: false
  property bool loadExited: false

  function signatureFor(value) {
    return value ? [value.layout, value.variant, keyboardModel, keyboardOptions].join("\u0000") : ""
  }

  // Let related input bindings settle before starting a request.
  onSignatureChanged: Qt.callLater(load)
  onLayoutsChanged: Qt.callLater(load)
  onActiveChanged: Qt.callLater(load)

  function load() {
    if (!active || !layout) return
    enqueue(layout, true)
    // Keep the requested layout ahead of background jobs.
    layouts.forEach(function(value) {
      if (signatureFor(value) !== signature) enqueue(value, false)
    })
  }

  function enqueue(value, first) {
    var sig = signatureFor(value)
    if (keymaps[sig] || sig === loadingSignature) return
    var rest = loadQueue.filter(function(job) { return job.signature !== sig })
    var job = { signature: sig, layout: value.layout, variant: value.variant,
      model: keyboardModel, options: keyboardOptions }
    loadQueue = first ? [job].concat(rest) : rest.concat([job])
    if (failures[sig]) {
      var next = Object.assign({}, failures)
      delete next[sig]
      failures = next
    }
    startNextLoad()
  }

  function startNextLoad() {
    if (keymapProc.running || loadingSignature !== "" || loadQueue.length === 0) return
    var job = loadQueue[0]
    loadQueue = loadQueue.slice(1)
    loadingSignature = job.signature
    loadStreamDone = false
    loadExited = false
    streamTimeout.stop()
    keymapProc.command = ["python3", "-B", scriptPath, job.layout, job.variant, job.model, job.options]
    keymapProc.running = true
  }

  function keymapRead(text) {
    if (loadingSignature === "") return
    loadStreamDone = true
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.keys && typeof parsed.keys === "object" && !Array.isArray(parsed.keys)) {
        var next = Object.assign({}, keymaps)
        next[loadingSignature] = parsed
        keymaps = next
      }
    } catch (e) {}
    finishLoad()
  }

  function finishLoad() {
    if (loadingSignature === "" || !loadStreamDone || !loadExited) return
    if (!keymaps[loadingSignature]) {
      var next = Object.assign({}, failures)
      next[loadingSignature] = true
      failures = next
    }
    streamTimeout.stop()
    loadingSignature = ""
    // Start after the previous process has finished delivering its signals.
    Qt.callLater(startNextLoad)
  }

  Process {
    id: keymapProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keymapRead(text)
    }
    onRunningChanged: if (!running && root.loadingSignature !== "") {
      root.loadExited = true
      // A process that never started has no output to wait for.
      streamTimeout.restart()
      root.finishLoad()
    }
  }

  Timer {
    id: streamTimeout
    interval: 500
    onTriggered: if (!root.loadStreamDone && root.loadExited) {
      root.loadStreamDone = true
      root.finishLoad()
    }
  }
}
