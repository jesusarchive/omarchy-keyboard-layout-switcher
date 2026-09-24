import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// One service for layout state, switching, IPC, and the switcher overlay.
// Bar widgets read this state on each monitor.
Item {
  id: root

  readonly property string pluginId: "jesusarchive.keyboard-layout-switcher"

  // Set by the shell host.
  property var shell: null
  property var manifest: null
  property var layouts: []
  property int activeIndex: 0
  property var keyboards: []
  property string keyboardModel: ""
  property string keyboardOptions: ""
  property bool capsLock: false
  // Set by the bar widget from its keyboardViewerGeometry setting.
  property string viewerGeometry: "auto"
  property bool loaded: false
  property var recent: []

  readonly property var activeLayout: layouts.length > 0 ? layouts[Math.max(0, Math.min(activeIndex, layouts.length - 1))] : null
  readonly property bool viewerOpened: viewer.opened

  property var _catalog: ({})
  property string _typedKeyboardName: ""
  property bool _refreshPending: false
  // Track the starting layout so a switcher run updates recent history once.
  property int _switcherOrigin: -1
  property var _menuHosts: []

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
    keyboardModel = state.keyboardModel
    keyboardOptions = state.keyboardOptions
    capsLock = state.capsLock
    if (JSON.stringify(state.layouts) !== JSON.stringify(layouts)) layouts = state.layouts
    // Ignore stale reads immediately after a switch.
    if (!switchGuard.running && state.activeIndex !== activeIndex) {
      activeIndex = state.activeIndex
      if (!hud.opened) recent = Model.touchRecent(recent, activeIndex, layouts.length)
    }
    if (!loaded) {
      loaded = true
      recent = Model.touchRecent(recent, activeIndex, layouts.length)
    }
  }

  // -------------------------------------------------------------- switching

  // A running Process cannot be started again. Detached commands allow another
  // switch before the previous command exits.
  function switchTo(index) {
    if (index < 0 || index >= layouts.length || keyboards.length === 0) return false
    if (index !== activeIndex) {
      var commands = Model.switchCommands(keyboards, index)
      for (var i = 0; i < commands.length; i++) Quickshell.execDetached(commands[i])
      activeIndex = index
      switchGuard.restart()
    }
    return true
  }

  // Ctrl+Space switches to the last used layout. Further presses cycle while
  // Ctrl is held. The overlay handles Space during its keyboard grab; ignore
  // duplicate binding calls that arrive just after it handles a key.
  function previous() {
    if (layouts.length < 2) return "single"
    if (advanceGuard.running || (hud.grabbing && hud.sawKeyRecently(400)))
      return activeLayout ? activeLayout.code : ""
    var target
    if (hud.opened) {
      target = Model.nextIndex(activeIndex, layouts.length)
    } else {
      _switcherOrigin = activeIndex
      target = Model.previousIndex(recent, activeIndex, layouts.length)
    }
    switchTo(target)
    hud.show()
    return activeLayout ? activeLayout.code : ""
  }

  // Space handled by the overlay instead of the Hyprland binding.
  function advance() {
    if (layouts.length < 2) return
    advanceGuard.restart()
    switchTo(Model.nextIndex(activeIndex, layouts.length))
    hud.show()
  }

  // Steps to the next layout in order.
  function next() {
    if (layouts.length < 2) return "single"
    select(Model.nextIndex(activeIndex, layouts.length))
    return activeLayout ? activeLayout.code : ""
  }

  // Direct selection from the menu or IPC.
  function select(index) {
    if (!switchTo(index)) return false
    recent = Model.touchRecent(recent, index, layouts.length)
    return true
  }

  function commitSwitcher() {
    if (_switcherOrigin >= 0) recent = Model.touchRecent(recent, _switcherOrigin, layouts.length)
    recent = Model.touchRecent(recent, activeIndex, layouts.length)
    _switcherOrigin = -1
  }

  // -------------------------------------------------------------- menu hosts

  // Choose the bar widget on the focused monitor for IPC menu toggles.
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

  function toggleViewer() { viewer.toggle() }

  Component.onCompleted: {
    catalogProc.running = true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      // Both activelayout event variants name the keyboard first.
      if (name.indexOf("activelayout") === 0) {
        if (Model.isVirtualKeyboardEvent(event.data)) return
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
    function set(layout: string): string {
      var index = Model.resolveLayout(root.layouts, layout)
      if (index < 0) return "unknown"
      root.select(index)
      return root.layouts[index].code
    }
    function current(): string { return root.activeLayout ? root.activeLayout.code : "" }
    function list(): string {
      return JSON.stringify(root.layouts.map(function(s) {
        return { index: s.index, code: s.code, layout: s.layout, variant: s.variant, name: s.name, active: s.index === root.activeIndex }
      }))
    }
    function toggle(): string { return root.toggleMenu() ? "ok" : "no bar widget" }
    function viewer(): string { root.toggleViewer(); return "ok" }
  }

  // Read layout names from xkb once at startup.
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

  // Cancel a stalled device read so later refreshes can run, then retry.
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

  // Hyprland sends no keyboard-added event here. Poll when multiple layouts
  // are configured so newly connected keyboards join later switches.
  Timer {
    interval: 10000
    repeat: true
    running: !root.loaded || root.layouts.length > 1
    onTriggered: root.refresh()
  }

  Timer {
    id: switchGuard
    interval: 350
    onTriggered: root.refresh()
  }

  // Suppress the duplicate binding call that follows a grabbed Space key.
  Timer {
    id: advanceGuard
    interval: 250
  }

  SwitchHud {
    id: hud
    service: root
    onSwitcherClosed: root.commitSwitcher()
    onAdvanceRequested: root.advance()
  }

  KeyboardViewer {
    id: viewer
    service: root
  }
}
