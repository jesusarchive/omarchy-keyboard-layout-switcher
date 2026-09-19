import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// One instance for the whole shell. It owns the layout state, the switching,
// the IPC target the key bindings call, and the switcher overlay. The bar
// widget, one per monitor, only renders what this exposes.
Item {
  id: root

  readonly property string pluginId: "jesusarchive.language-switcher"

  // The host fills these in.
  property var shell: null
  property var manifest: null
  // The bar widget pushes these across from its shell.json entry.
  property var settings: ({})

  property var sources: []
  property int activeIndex: 0
  property var keyboards: []
  property bool loaded: false
  property var recent: []

  readonly property var activeSource: sources.length > 0 ? sources[Math.max(0, Math.min(activeIndex, sources.length - 1))] : null

  readonly property bool showSwitcher: setting("showSwitcher", true) !== false
  readonly property int hudTimeoutMs: intSetting("hudTimeoutMs", 900, 300, 5000)

  property var _catalog: ({})
  property string _typedKeyboardName: ""
  property bool _refreshPending: false
  // Where the switcher started, so a run of presses adds one
  // most-recently-used entry rather than one per press.
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
    if (JSON.stringify(state.sources) !== JSON.stringify(sources)) sources = state.sources
    // A reading that lands right after our own switch can predate it.
    if (!switchGuard.running && state.activeIndex !== activeIndex) {
      activeIndex = state.activeIndex
      if (!hud.opened) recent = Model.touchRecent(recent, activeIndex, sources.length)
    }
    if (!loaded) {
      loaded = true
      recent = Model.touchRecent(recent, activeIndex, sources.length)
    }
  }

  // -------------------------------------------------------------- switching

  // Detached argv rather than a Process. A Process that is already running
  // can't be re-run, so Quickshell would discard a second Ctrl+Space that
  // arrived inside the first switch. activeIndex has already moved by then, so
  // the badge would name a layout nobody is on.
  function switchTo(index) {
    if (index < 0 || index >= sources.length || keyboards.length === 0) return false
    if (index !== activeIndex) {
      var commands = Model.switchCommands(keyboards, index)
      for (var i = 0; i < commands.length; i++) Quickshell.execDetached(commands[i])
      activeIndex = index
      switchGuard.restart()
    }
    return true
  }

  // Ctrl+Space. The first press goes back to the previously used source and
  // opens the switcher. Each further press while the switcher is still up moves
  // down the list. Each press restarts the hudTimeoutMs window, so the run ends
  // when the reader stops pressing. Hyprland reports the press and never the
  // release, so there is nothing else to end it on.
  function previous() {
    if (sources.length < 2) return "single"
    var target
    if (hud.opened) {
      target = Model.nextIndex(activeIndex, sources.length)
    } else {
      _switcherOrigin = activeIndex
      target = Model.previousIndex(recent, activeIndex, sources.length)
    }
    switchTo(target)
    if (showSwitcher) hud.show()
    else commitSwitcher()
    return activeSource ? activeSource.code : ""
  }

  // Steps to the next source in order.
  function next() {
    if (sources.length < 2) return "single"
    select(Model.nextIndex(activeIndex, sources.length))
    return activeSource ? activeSource.code : ""
  }

  // Handles a direct pick from the menu or the IPC target.
  function select(index) {
    if (!switchTo(index)) return false
    recent = Model.touchRecent(recent, index, sources.length)
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
      // activelayout and the newer activelayoutv2 both name the keyboard first.
      if (name.indexOf("activelayout") === 0) {
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

  // xkb's own names for every layout, so "es" gives "Spanish". This only
  // changes when the xkb data package gets an upgrade, so read it once.
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
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }
      stallTimer.stop()
      if (root._refreshPending) root.refresh()
    }
  }

  // A reading that never comes back would freeze the badge until the shell
  // restarts, since a Process that is already running can't be re-run. Drop one
  // that overstays so the next refresh gets through, then ask again. The
  // reading it never delivered may have been the only one due.
  Timer {
    id: stallTimer
    interval: 5000
    onTriggered: {
      devicesProc.running = false
      retryTimer.restart()
    }
  }

  Timer {
    id: retryTimer
    interval: 600
    onTriggered: root.refresh()
  }

  // Plugging a keyboard in raises no Hyprland event, so a stale list would
  // leave that keyboard on the old layout whichever way the switch runs. Poll
  // whenever switching is possible at all. A single-layout install has nothing
  // to switch, so it skips the poll rather than spawning hyprctl forever.
  Timer {
    interval: 10000
    repeat: true
    running: !root.loaded || root.sources.length > 1
    onTriggered: root.refresh()
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
