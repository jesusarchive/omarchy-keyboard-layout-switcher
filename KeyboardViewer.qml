import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Typing.js" as Typing
import "ViewerLayout.js" as ViewerLayout

// A floating map of the active XKB layout. It leaves keyboard focus with the
// application underneath, so clicked keys type there through wtype.
Item {
  id: root
  required property var service

  property bool opened: false
  property var targetScreen: null
  // Shift, Caps, AltGr, shortcut modifiers and a pending dead key; see Typing.js.
  property var typing: Typing.initialState(false)

  // Keymaps from keyboard_viewer.py, cached by signature so switching layouts
  // never blanks the keys.
  property var keymaps: ({})
  property var keymap: null
  property string errorText: ""
  property var loadQueue: []
  property string loadingSignature: ""
  property bool loadStreamDone: false
  property bool loadExited: false

  property var typeQueue: []
  property var activeCommand: []

  // Held Backspace, Space and arrows repeat the command from the first press.
  property string repeatKey: ""
  property var repeatCommand: null

  property var accentChoices: []
  property string accentKeyId: ""
  property real accentPopupX: 0
  property real accentPopupY: 0

  // Width chosen with the resize grip, and dragged positions per monitor, for
  // this session. 0 means the default width.
  property real chosenWidth: 0
  property var positions: ({})

  readonly property var shown: Typing.displayState(typing)
  readonly property var activeLayout: service.activeLayout
  readonly property string signature: signatureFor(activeLayout)
  readonly property string geometryName: ViewerLayout.geometryFor(service.viewerGeometry,
    activeLayout ? activeLayout.layout : "", service.keyboardModel)
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("keyboard_viewer.py")).replace(/^file:\/\//, ""))

  readonly property real screenWidth: targetScreen ? targetScreen.width : panel.width
  readonly property real screenHeight: targetScreen ? targetScreen.height : panel.height
  readonly property real screenMargin: Style.space(24)
  readonly property real minWidth: Style.space(480)
  readonly property real maxWidth: Math.max(minWidth, screenWidth - 2 * screenMargin)
  readonly property real viewerWidth: Math.max(minWidth, Math.min(maxWidth, chosenWidth > 0 ? chosenWidth : Style.space(760)))

  readonly property var namedKeys: ({
    ESC: "esc", BKSP: "⌫", TAB: "⇥", RTRN: "⏎", LFSH: "⇧", RTSH: "⇧",
    LCTL: "ctrl", LWIN: "super", LALT: "alt", SPCE: " ",
    LEFT: "◀", UP: "▲", DOWN: "▼", RGHT: "▶"
  })

  function signatureFor(layout) {
    return layout ? [layout.layout, layout.variant, service.keyboardModel, service.keyboardOptions].join("\u0000") : ""
  }

  function focusedScreen() {
    var wanted = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (String(Quickshell.screens[i].name) === wanted) return Quickshell.screens[i]
    return Quickshell.screens.length ? Quickshell.screens[0] : null
  }

  function toggle() {
    if (opened) { close(); return }
    targetScreen = focusedScreen()
    typing = Typing.initialState(service.capsLock)
    closeAccents()
    opened = true
    placeCard()
    load()
    // Pick up the physical Caps Lock state.
    service.refresh()
  }

  function close() {
    stopRepeat()
    closeAccents()
    opened = false
  }

  onSignatureChanged: {
    typing = Typing.press(null, typing, "ESC", 0).state
    closeAccents()
    if (opened) load()
  }

  Connections {
    target: root.service
    function onCapsLockChanged() {
      if (!root.opened || root.typing.caps === root.service.capsLock) return
      var next = Object.assign({}, root.typing)
      next.caps = root.service.capsLock
      root.typing = next
    }
  }

  // ------------------------------------------------------------ keymaps

  function load() {
    if (!activeLayout) return
    if (keymaps[signature]) {
      keymap = keymaps[signature]
      errorText = ""
    } else {
      enqueue(activeLayout, true)
    }
    // Load the other configured layouts in the background.
    service.layouts.forEach(function(layout) { enqueue(layout, false) })
  }

  function enqueue(layout, first) {
    var sig = signatureFor(layout)
    if (keymaps[sig] || sig === loadingSignature) return
    var rest = loadQueue.filter(function(job) { return job.signature !== sig })
    var job = { signature: sig, layout: layout.layout, variant: layout.variant }
    loadQueue = first ? [job].concat(rest) : rest.concat([job])
    startNextLoad()
  }

  function startNextLoad() {
    if (keymapProc.running || loadingSignature !== "" || loadQueue.length === 0) return
    var job = loadQueue[0]
    loadQueue = loadQueue.slice(1)
    loadingSignature = job.signature
    loadStreamDone = false
    loadExited = false
    keymapProc.command = ["python3", "-B", scriptPath, job.layout, job.variant,
      service.keyboardModel, service.keyboardOptions]
    keymapProc.running = true
  }

  function keymapRead(text) {
    loadStreamDone = true
    try {
      var parsed = JSON.parse(text)
      var next = Object.assign({}, keymaps)
      next[loadingSignature] = parsed
      keymaps = next
      if (loadingSignature === signature) {
        keymap = parsed
        errorText = ""
      }
    } catch (e) {}
    finishLoad()
  }

  function finishLoad() {
    if (!loadStreamDone || !loadExited) return
    if (loadingSignature === signature && !keymaps[signature])
      errorText = "Could not read this keyboard layout"
    loadingSignature = ""
    startNextLoad()
  }

  Process {
    id: keymapProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.keymapRead(text)
    }
    onRunningChanged: if (!running) {
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

  // ------------------------------------------------------------- typing

  function queueType(command) {
    typeQueue = typeQueue.concat([command])
    startNextType()
  }

  function startNextType() {
    if (typeProc.running || typeQueue.length === 0) return
    activeCommand = typeQueue[0]
    typeQueue = typeQueue.slice(1)
    typeProc.running = true
  }

  Process {
    id: typeProc
    command: root.activeCommand
    onExited: root.startNextType()
  }

  function act(id) {
    var result = Typing.press(keymap, typing, id, Date.now())
    typing = result.state
    result.commands.forEach(queueType)
    return result
  }

  // Repeating keys type on press; everything else types on click, so a press
  // and hold on a letter can open the accent popup instead.
  function pressKey(id) {
    if (!Typing.isRepeating(id)) return
    closeAccents()
    var result = act(id)
    repeatKey = id
    repeatCommand = result.commands.length ? result.commands[result.commands.length - 1] : null
    repeatTimer.interval = 400
    repeatTimer.restart()
  }

  function releaseKey(id) {
    if (repeatKey === id) stopRepeat()
  }

  function stopRepeat() {
    repeatTimer.stop()
    repeatKey = ""
    repeatCommand = null
  }

  function clickKey(id) {
    if (Typing.isRepeating(id)) return
    if (accentKeyId === id) { closeAccents(); return }
    closeAccents()
    act(id)
  }

  function holdKey(id, face, mouse) {
    var choices = Typing.isRepeating(id) ? [] : Typing.accentsFor(keymap, id, typing)
    if (choices.length === 0) {
      // Let the click through so a slow click still types.
      mouse.accepted = false
      return
    }
    openAccents(id, choices, face)
  }

  Timer {
    id: repeatTimer
    repeat: true
    onTriggered: {
      interval = 50
      // Skip a beat rather than build a backlog that types after release.
      if (root.repeatCommand && !typeProc.running && root.typeQueue.length === 0)
        root.queueType(root.repeatCommand)
    }
  }

  function openAccents(id, choices, face) {
    var cell = Style.space(36)
    var spacing = Style.space(3)
    var popupWidth = choices.length * cell + (choices.length - 1) * spacing + Style.space(8)
    var popupHeight = cell + Style.space(8)
    var point = face.mapToItem(card, 0, 0)
    accentPopupX = Math.max(card.contentLeftInset, Math.min(point.x + face.width / 2 - popupWidth / 2,
      card.width - card.contentRightInset - popupWidth))
    var above = point.y - popupHeight - Style.space(4)
    accentPopupY = above >= card.contentTopInset ? above : point.y + face.height + Style.space(4)
    accentChoices = choices
    accentKeyId = id
  }

  function closeAccents() {
    accentChoices = []
    accentKeyId = ""
  }

  function chooseAccent(text) {
    var result = Typing.choose(typing, text)
    typing = result.state
    result.commands.forEach(queueType)
    closeAccents()
  }

  // --------------------------------------------------------- key faces

  function isLayoutKey(id) {
    return !namedKeys[id] && id !== "CAPS" && id !== "RALT" && !Typing.specialKeysym(id)
  }

  function keyEntry(id) {
    var current = Typing.entry(keymap, id, shown)
    if ((!current || !current.keysym) && Typing.isChord(typing))
      return Typing.entry(keymap, id, { shift: 0, caps: false, altgr: 0 })
    return current
  }

  function labelFor(id) {
    if (id === "CAPS") return "⇪"
    if (id === "RALT") return Typing.hasAltGr(keymap) ? "alt gr" : "alt"
    if (namedKeys[id]) return namedKeys[id]
    var fn = Typing.specialKeysym(id)
    if (fn) return fn
    var current = keyEntry(id)
    return current ? current.label : ""
  }

  function enabledFor(id) {
    if (!isLayoutKey(id)) return true
    var current = keyEntry(id)
    return !!current && !!current.keysym
  }

  // 0 off, 1 latched for one key, 2 locked.
  function latchFor(id) {
    if (id === "CAPS") return typing.caps ? Typing.LOCKED : 0
    var name = Typing.modifierFor(id, keymap)
    return name ? typing[name] : 0
  }

  // ------------------------------------------------------------ placement

  function clampX(x) { return Math.max(0, Math.min(x, screenWidth - card.width)) }
  function clampY(y) { return Math.max(0, Math.min(y, screenHeight - card.height)) }

  // Open in the center of the screen. A position dragged this session wins.
  function placeCard() {
    var saved = positions[screenKey()]
    if (saved) {
      card.x = clampX(saved.x)
      card.y = clampY(saved.y)
    } else {
      card.x = Math.round((screenWidth - card.width) / 2)
      card.y = Math.round((screenHeight - card.height) / 2)
    }
  }

  function screenKey() { return targetScreen ? String(targetScreen.name) : "" }

  function rememberPosition() {
    var next = Object.assign({}, positions)
    next[screenKey()] = { x: card.x, y: card.y }
    positions = next
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen || (Quickshell.screens.length ? Quickshell.screens[0] : null)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jesusarchive-keyboard-viewer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }

    // Drag target for the resize grip; lives outside the card so resizing
    // does not move it.
    Item { id: resizeProxy; width: 1; height: 1 }

    BorderSurface {
      id: card
      width: root.viewerWidth
      height: viewerColumn.implicitHeight + viewerColumn.y + contentBottomInset
      radius: Math.max(Style.cornerRadius, Style.space(12))
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
      padding: Style.spacing.panelPadding

      readonly property real innerWidth: width - contentLeftInset - contentRightInset
      readonly property real gap: Math.max(3, Math.round(innerWidth / ViewerLayout.ROWS * 0.08))
      readonly property real pitch: (innerWidth + gap) / ViewerLayout.ROWS
      readonly property var placed: ViewerLayout.place(root.geometryName, pitch, gap)

      // Keep the whole card on screen when it grows or changes shape.
      onHeightChanged: if (root.opened) y = root.clampY(y)
      onWidthChanged: if (root.opened) x = root.clampX(x)

      // Clicking empty space closes the accent popup.
      MouseArea {
        anchors.fill: parent
        onClicked: root.closeAccents()
      }

      Column {
        id: viewerColumn
        x: card.contentLeftInset
        y: card.gap * 2
        width: card.innerWidth
        spacing: card.gap

        // Title bar: the title in the middle, close on the right as elsewhere
        // on Linux.
        Item {
          width: parent.width
          height: Math.round(card.pitch * 0.46)

          MouseArea {
            id: dragArea
            x: -card.contentLeftInset
            y: -viewerColumn.y
            width: card.width
            height: parent.height + viewerColumn.y
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: card
            drag.axis: Drag.XAndYAxis
            drag.threshold: 2
            drag.minimumX: 0
            drag.maximumX: root.screenWidth - card.width
            drag.minimumY: 0
            drag.maximumY: root.screenHeight - card.height
            onReleased: root.rememberPosition()
          }

          Rectangle {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(card.pitch * 0.46)
            height: width
            radius: width / 2
            color: Util.alpha(Color.menu.text, closeArea.pressed ? 0.32 : closeArea.containsMouse ? 0.22 : 0.12)
            Behavior on color { ColorAnimation { duration: 70 } }

            Text {
              anchors.centerIn: parent
              text: "×"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Math.round(parent.height * 0.8)
            }

            MouseArea {
              id: closeArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }

          Text {
            anchors.centerIn: parent
            text: "Keyboard"
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.bold: true
            font.pixelSize: Math.round(card.pitch * 0.26)
          }
        }

        Item {
          id: keyboard
          width: parent.width
          height: card.placed.height

          Repeater {
            model: card.placed.keys

            Item {
              id: cap
              required property var modelData
              readonly property string keyId: modelData.id
              readonly property bool isL: modelData.cutW > 0
              // The L-shaped Enter has two mouse areas; either one counts.
              readonly property bool hovered: live && anyArea("containsMouse")
              readonly property bool down: live && anyArea("pressed")

              function anyArea(property) {
                for (var i = 0; i < areas.count; i++) {
                  var area = areas.itemAt(i)
                  if (area && area[property]) return true
                }
                return false
              }
              readonly property bool live: root.enabledFor(keyId)
              readonly property int latch: root.latchFor(keyId)
              readonly property bool armed: root.typing.deadId === keyId && root.typing.dead !== ""
              readonly property bool layoutKey: root.isLayoutKey(keyId)
              readonly property string label: root.labelFor(keyId)
              readonly property string alternate: layoutKey && Typing.showsAlternates(root.typing)
                ? Typing.alternateLabel(root.keymap, keyId, root.shown) : ""
              readonly property bool deadKey: layoutKey && !Typing.isChord(root.typing)
                && Typing.isDeadKey(root.keymap, keyId, root.shown)

              // Flat keys with a hairline edge, as on the macOS keyboard.
              // Hover brightens the edge. As with macOS sticky keys, a latched
              // modifier gets an accent outline and a locked one (double-click,
              // or Caps Lock) an accent fill. Dead keys keep an accent outline.
              readonly property bool locked: latch === Typing.LOCKED
              readonly property color faceColor: !live ? Util.alpha(Color.menu.text, 0.04)
                : locked ? Util.alpha(Color.accent, 0.38)
                : down ? Util.alpha(Color.menu.text, 0.34)
                : armed ? Util.alpha(Color.accent, 0.22)
                : hovered ? Util.alpha(Color.menu.text, 0.2)
                : Util.alpha(Color.menu.text, 0.1)
              readonly property color edgeColor: latch > 0 || armed ? Color.accent
                : hovered || down ? Util.alpha(Color.menu.text, 0.9)
                : deadKey ? Color.accent
                : Util.alpha(Color.menu.text, live ? 0.32 : 0.14)
              readonly property bool strongEdge: hovered || down || latch > 0 || armed || deadKey
              readonly property color inkColor: Util.alpha(Color.menu.text, live ? 1 : 0.3)

              x: modelData.x
              y: modelData.y
              width: modelData.w
              height: modelData.h

              KeyFace {
                id: face
                anchors.fill: parent
                lShape: cap.isL
                cutW: cap.modelData.cutW
                cutY: cap.modelData.cutY
                fill: cap.faceColor
                edge: cap.edgeColor
                edgeWidth: cap.strongEdge ? 1.5 : 1
              }

              Item {
                // The L-shaped Enter centers its label on the full-height column.
                x: cap.isL ? cap.modelData.cutW : 0
                width: parent.width - x
                height: parent.height

                Text {
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: cap.alternate ? card.pitch * 0.1 : 0
                  anchors.verticalCenterOffset: cap.alternate ? card.pitch * 0.08 : 0
                  width: parent.width - Style.space(4)
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: cap.label
                  textFormat: Text.PlainText
                  color: cap.inkColor
                  font.family: "Noto Sans"
                  font.pixelSize: Math.max(8, Math.round(card.pitch * (cap.layoutKey ? 0.36 : cap.label.length > 2 ? 0.22 : 0.3)))
                }

                Text {
                  visible: cap.alternate.length > 0
                  x: Math.round(card.pitch * 0.1)
                  y: Math.round(card.pitch * 0.04)
                  text: cap.alternate
                  textFormat: Text.PlainText
                  color: Util.alpha(Color.menu.text, 0.65)
                  font.family: "Noto Sans"
                  font.pixelSize: Math.max(8, Math.round(card.pitch * 0.22))
                }
              }

              Repeater {
                id: areas
                model: cap.modelData.rects

                MouseArea {
                  required property var modelData
                  x: modelData.x
                  y: modelData.y
                  width: modelData.w
                  height: modelData.h
                  hoverEnabled: true
                  enabled: cap.live
                  pressAndHoldInterval: 450
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onPressedChanged: {
                    if (pressed) root.pressKey(cap.keyId)
                    else root.releaseKey(cap.keyId)
                  }
                  onCanceled: root.releaseKey(cap.keyId)
                  onPressAndHold: function(mouse) { root.holdKey(cap.keyId, face, mouse) }
                  onClicked: root.clickKey(cap.keyId)
                  // Qt suppresses onClicked for the second click. Repeating
                  // keys already act on press; other keys need this second act.
                  onDoubleClicked: root.clickKey(cap.keyId)
                }
              }
            }
          }
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width
          text: root.errorText
          textFormat: Text.PlainText
          color: Color.menu.text
          opacity: 0.7
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }
      }

      // Resize grip. The keys keep their proportions, so width sets the size.
      MouseArea {
        id: resizeArea
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(18)
        height: width
        hoverEnabled: true
        cursorShape: Qt.SizeFDiagCursor
        drag.target: resizeProxy
        drag.threshold: 0
        property real startWidth: 0
        onPressed: {
          resizeProxy.x = 0
          startWidth = card.width
        }
        onReleased: root.rememberPosition()

        Connections {
          target: resizeProxy
          function onXChanged() {
            if (resizeArea.pressed) root.chosenWidth = Math.max(root.minWidth,
              Math.min(root.screenWidth - card.x, resizeArea.startWidth + resizeProxy.x))
          }
        }

        Canvas {
          anchors.fill: parent
          anchors.margins: Style.space(4)
          opacity: resizeArea.containsMouse || resizeArea.pressed ? 0.8 : 0.35
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Color.menu.text
            ctx.lineWidth = 1
            for (var i = 1; i <= 2; i++) {
              ctx.beginPath()
              ctx.moveTo(width, height - width * i / 2)
              ctx.lineTo(width - width * i / 2, height)
              ctx.stroke()
            }
          }
        }
      }

      Rectangle {
        visible: root.accentChoices.length > 0
        z: 10
        x: root.accentPopupX
        y: root.accentPopupY
        width: accentRow.implicitWidth + Style.space(8)
        height: accentRow.implicitHeight + Style.space(8)
        radius: Style.space(6)
        color: Color.menu.background
        border.width: 1
        border.color: Color.menu.selectedText

        // Swallow clicks between choices so they do not reach the card.
        MouseArea { anchors.fill: parent }

        Row {
          id: accentRow
          anchors.centerIn: parent
          spacing: Style.space(3)

          Repeater {
            model: root.accentChoices

            Rectangle {
              required property string modelData
              width: Style.space(36)
              height: Style.space(36)
              radius: Style.space(4)
              color: choiceArea.pressed ? Util.alpha(Color.menu.text, 0.32)
                : choiceArea.containsMouse ? Util.alpha(Color.menu.text, 0.22)
                : Util.alpha(Color.menu.text, 0.12)
              border.width: choiceArea.containsMouse ? 1.5 : 1
              border.color: choiceArea.containsMouse ? Util.alpha(Color.menu.text, 0.9) : Util.alpha(Color.menu.text, 0.5)
              Behavior on color { ColorAnimation { duration: 70 } }

              Text {
                anchors.centerIn: parent
                text: modelData
                textFormat: Text.PlainText
                color: Color.menu.text
                font.family: "Noto Sans"
                font.pixelSize: Style.font.heading + 3
              }

              MouseArea {
                id: choiceArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.chooseAccent(modelData)
              }
            }
          }
        }
      }
    }
  }

  // A key face: a rounded rectangle, or the L-shaped ISO Enter.
  component KeyFace: Item {
    id: keyFace
    property bool lShape: false
    property real cutW: 0
    property real cutY: 0
    property color fill: "transparent"
    property color edge: "transparent"
    property real edgeWidth: 1
    readonly property real radius: Math.max(3, Math.min(Style.space(6), width * 0.1))

    Behavior on fill { ColorAnimation { duration: 70 } }
    Behavior on edge { ColorAnimation { duration: 70 } }

    Rectangle {
      visible: !keyFace.lShape
      anchors.fill: parent
      radius: keyFace.radius
      color: keyFace.fill
      border.width: keyFace.edgeWidth
      border.color: keyFace.edge
    }

    Shape {
      visible: keyFace.lShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        readonly property real r: keyFace.radius
        readonly property real w: keyFace.width
        readonly property real h: keyFace.height
        readonly property real inset: keyFace.edgeWidth / 2
        fillColor: keyFace.fill
        strokeColor: keyFace.edgeWidth > 0 ? keyFace.edge : "transparent"
        strokeWidth: keyFace.edgeWidth
        startX: r; startY: inset
        PathLine { x: keyFace.width - keyFace.radius; y: keyFace.edgeWidth / 2 }
        PathArc { x: keyFace.width - keyFace.edgeWidth / 2; y: keyFace.radius; radiusX: keyFace.radius; radiusY: keyFace.radius }
        PathLine { x: keyFace.width - keyFace.edgeWidth / 2; y: keyFace.height - keyFace.radius }
        PathArc { x: keyFace.width - keyFace.radius; y: keyFace.height - keyFace.edgeWidth / 2; radiusX: keyFace.radius; radiusY: keyFace.radius }
        PathLine { x: keyFace.cutW + keyFace.radius; y: keyFace.height - keyFace.edgeWidth / 2 }
        PathArc { x: keyFace.cutW + keyFace.edgeWidth / 2; y: keyFace.height - keyFace.radius; radiusX: keyFace.radius; radiusY: keyFace.radius }
        PathLine { x: keyFace.cutW + keyFace.edgeWidth / 2; y: keyFace.cutY - keyFace.edgeWidth / 2 }
        PathLine { x: keyFace.radius; y: keyFace.cutY - keyFace.edgeWidth / 2 }
        PathArc { x: keyFace.edgeWidth / 2; y: keyFace.cutY - keyFace.radius; radiusX: keyFace.radius; radiusY: keyFace.radius }
        PathLine { x: keyFace.edgeWidth / 2; y: keyFace.radius }
        PathArc { x: keyFace.radius; y: keyFace.edgeWidth / 2; radiusX: keyFace.radius; radiusY: keyFace.radius }
      }
    }
  }
}
