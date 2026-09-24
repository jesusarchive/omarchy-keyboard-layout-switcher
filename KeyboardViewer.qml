import QtQuick
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

  readonly property var keymap: keymapLoader.keymap
  readonly property string errorText: keymapLoader.errorText

  property var typeQueue: []
  property var activeCommand: []

  // Held Backspace, Space and arrows repeat the command from the first press.
  property string repeatKey: ""
  property var repeatCommand: null

  property var accentChoices: []
  property string accentKeyId: ""
  property real accentPopupX: 0
  property real accentPopupY: 0

  // Remember width and position for this session. A width of 0 uses the default.
  property real chosenWidth: 0
  property var positions: ({})

  readonly property var shown: Typing.displayState(typing)
  readonly property var activeLayout: service.activeLayout
  readonly property string signature: keymapLoader.signature
  readonly property string geometryName: ViewerLayout.geometryFor(service.viewerGeometry,
    activeLayout ? activeLayout.layout : "", service.keyboardModel)

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
    // Sync the physical Caps Lock state.
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
    stopRepeat()
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

  KeymapLoader {
    id: keymapLoader
    active: root.opened
    layout: root.activeLayout
    layouts: root.service.layouts
    keyboardModel: root.service.keyboardModel
    keyboardOptions: root.service.keyboardOptions
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
    if (!keymapLoader.ready) return { state: typing, commands: [] }
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
      // Skip repeat events while the previous command runs.
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
    if (!keymapLoader.ready) return
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
    if (!keymapLoader.ready) return false
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

  // Open at a position dragged earlier this session, or in the center.
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
      readonly property real gap: Math.max(3, Math.round(innerWidth / ViewerLayout.ROW_UNITS * 0.08))
      readonly property real pitch: (innerWidth + gap) / ViewerLayout.ROW_UNITS
      readonly property var placed: ViewerLayout.place(root.geometryName, pitch, gap)

      // Keep the whole card on screen when it grows or changes shape.
      onHeightChanged: if (root.opened) y = root.clampY(y)
      onWidthChanged: if (root.opened) x = root.clampX(x)

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeAccents()
      }

      Column {
        id: viewerColumn
        x: card.contentLeftInset
        y: card.gap * 3
        width: card.innerWidth
        spacing: card.gap * 2

        Item {
          width: parent.width
          height: Math.round(card.pitch * 0.56)

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

            KeyboardKey {
              id: cap
              required property var modelData
              readonly property string keyId: modelData.id
              geometry: modelData
              pitch: card.pitch
              live: root.enabledFor(keyId)
              latched: root.latchFor(keyId) > 0
              locked: root.latchFor(keyId) === Typing.LOCKED
              armed: root.typing.deadId === keyId && root.typing.dead !== ""
              layoutKey: root.isLayoutKey(keyId)
              label: root.labelFor(keyId)
              alternate: layoutKey && Typing.showsAlternates(root.typing)
                ? Typing.alternateLabel(root.keymap, keyId, root.shown) : ""
              deadKey: layoutKey && !Typing.isChord(root.typing)
                && Typing.isDeadKey(root.keymap, keyId, root.shown)
              onKeyPressed: root.pressKey(keyId)
              onKeyReleased: root.releaseKey(keyId)
              onKeyClicked: root.clickKey(keyId)
              onKeyHeld: function(mouse) { root.holdKey(keyId, cap, mouse) }
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
}
