import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// One instance for the whole shell. Owns the layout state, the switching,
// the IPC target the key bindings call, and the switch overlays. The bar
// widget (one per monitor) only renders what this exposes.
Item {
  id: root

  readonly property string pluginId: "jesusarchive.language-switcher"

  // Host injection.
  property var shell: null
  property var manifest: null
  // Pushed by the bar widget from its shell.json entry.
  property var settings: ({})

  property var sources: []
  property int activeIndex: 0
  property var keyboards: []
  property bool capsLock: false
  property bool loaded: false
  property var recent: []

  readonly property var activeSource: sources.length > 0 ? sources[Math.max(0, Math.min(activeIndex, sources.length - 1))] : null

  readonly property bool showSwitcher: setting("showSwitcher", true) !== false
  readonly property bool showIndicator: setting("showIndicator", true) !== false
  readonly property int hudTimeoutMs: intSetting("hudTimeoutMs", 900, 300, 5000)

  property var _catalog: ({})
  property string _typedKeyboardName: ""
  property bool _refreshPending: false
  // Where the switcher started, so a run of presses commits one MRU entry.
  property int _switcherOrigin: -1
  property var _menuHosts: []

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // ---------------------------------------------------------------- reading

  function refresh() {
    if (devicesProc.running) {
      _refreshPending = true
      return
    }
    _refreshPending = false
    devicesProc.running = true
  }

  function applyDevices(text) {
    var state = Model.readDevices(text, _catalog, _typedKeyboardName)
    if (!state) return
    keyboards = state.keyboards
    capsLock = state.capsLock
    if (JSON.stringify(state.sources) !== JSON.stringify(sources)) sources = state.sources
    // A reading that lands right after our own switch can predate it.
    if (!switchGuard.running && state.activeIndex !== activeIndex) {
      activeIndex = state.activeIndex
      if (!hud.switcherOpen) recent = Model.touchRecent(recent, activeIndex, sources.length)
    }
    if (!loaded) {
      loaded = true
      recent = Model.touchRecent(recent, activeIndex, sources.length)
    }
  }

  // -------------------------------------------------------------- switching

  function switchTo(index) {
    if (index < 0 || index >= sources.length || keyboards.length === 0) return false
    if (index !== activeIndex) {
      switchProc.command = ["hyprctl", "--batch", Model.switchBatch(keyboards, index)]
      switchProc.running = true
      activeIndex = index
      switchGuard.restart()
    }
    return true
  }

  // Control-Space. The first press goes back to the previously used source and
  // opens the switcher; each press while it is still up moves down the list,
  // the way holding Control and tapping Space does on macOS.
  function previous() {
    if (sources.length < 2) return "single"
    var target
    if (hud.switcherOpen) {
      target = Model.nextIndex(activeIndex, sources.length)
    } else {
      _switcherOrigin = activeIndex
      target = Model.previousIndex(recent, activeIndex, sources.length)
    }
    switchTo(target)
    if (showSwitcher) hud.show("switcher")
    else commitSwitcher()
    return activeSource ? activeSource.code : ""
  }

  // Control-Option-Space: next source, with the small indicator.
  function next() {
    if (sources.length < 2) return "single"
    select(Model.nextIndex(activeIndex, sources.length))
    return activeSource ? activeSource.code : ""
  }

  // A direct pick (menu, IPC, right click).
  function select(index) {
    if (!switchTo(index)) return false
    recent = Model.touchRecent(recent, index, sources.length)
    if (showIndicator) hud.show("indicator")
    return true
  }

  function commitSwitcher() {
    if (_switcherOrigin >= 0) recent = Model.touchRecent(recent, _switcherOrigin, sources.length)
    recent = Model.touchRecent(recent, activeIndex, sources.length)
    _switcherOrigin = -1
  }

  // -------------------------------------------------------------- menu hosts

  // Each bar widget registers so `toggle` can open the menu on the monitor
  // that has focus.
  function registerMenuHost(host) {
    if (_menuHosts.indexOf(host) === -1) _menuHosts = _menuHosts.concat([host])
  }

  function unregisterMenuHost(host) {
    _menuHosts = _menuHosts.filter(function(h) { return h !== host })
  }

  function toggleMenu() {
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var hosts = _menuHosts.filter(function(h) { return h && typeof h.toggle === "function" })
    var host = hosts.find(function(h) { return h.screenName === focused }) || hosts[0]
    if (!host) return false
    host.toggle()
    return true
  }

  Component.onCompleted: {
    catalogProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "activelayout") {
        var named = Model.eventKeyboardName(event.data)
        if (named) root._typedKeyboardName = named
        root.refresh()
      } else if (name === "configreloaded") {
        root.refresh()
      }
    }
  }

  IpcHandler {
    target: root.pluginId

    function previous(): string { return root.previous() }
    function next(): string { return root.next() }
    function set(source: string): string {
      var index = Model.resolveSource(root.sources, source)
      if (index < 0) return "unknown"
      root.select(index)
      return root.sources[index].code
    }
    function current(): string { return root.activeSource ? root.activeSource.code : "" }
    function list(): string {
      return JSON.stringify(root.sources.map(function(s) {
        return { index: s.index, code: s.code, layout: s.layout, variant: s.variant, name: s.name, active: s.index === root.activeIndex }
      }))
    }
    function toggle(): string { return root.toggleMenu() ? "ok" : "no bar widget" }
    function refresh(): string { root.refresh(); return "ok" }
  }

  // xkb's own names for every layout ("es" → Spanish). Only changes when the
  // xkb data package is upgraded, so read it once.
  Process {
    id: catalogProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._catalog = Model.layoutCatalog(text)
    }
    onExited: root.refresh()
  }

  Process {
    id: devicesProc
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDevices(text)
    }
    onRunningChanged: if (!running && root._refreshPending) root.refresh()
  }

  Process {
    id: switchProc
    command: []
  }

  Timer {
    id: switchGuard
    interval: 350
    onTriggered: root.refresh()
  }

  SwitchHud {
    id: hud
    service: root
    onSwitcherClosed: root.commitSwitcher()
  }
}
