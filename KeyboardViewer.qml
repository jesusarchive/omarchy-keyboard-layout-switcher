import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Typing.js" as Typing

// A floating map of the active XKB layout. It leaves keyboard focus with the
// application underneath, so clicked keys can type there through wtype.
Item {
  id: root
  required property var service

  property bool opened: false
  property bool shifted: false
  property bool altGr: false
  property bool capsOn: false
  property string pendingDead: ""
  property string pendingDeadId: ""
  property var accentChoices: []
  property string accentKeyId: ""
  property real accentPopupX: 0
  property real accentPopupY: 0
  property var targetScreen: null
  property var keyLabels: ({})
  property string requestedSignature: ""
  property bool reloadPending: false
  property string errorText: ""
  property var typeQueue: []
  property var activeCommand: []

  readonly property var activeLayout: service.activeLayout
  readonly property string signature: activeLayout
    ? [activeLayout.layout, activeLayout.variant, service.keyboardModel, service.keyboardOptions].join("\u0000") : ""
  readonly property string scriptPath: decodeURIComponent(String(Qt.resolvedUrl("keyboard_viewer.py")).replace(/^file:\/\//, ""))
  readonly property int gap: Style.space(4)

  readonly property var rows: [
    [key("ESC", 1.2, "esc"), key("FK01", 1.1, "F1"), key("FK02", 1.1, "F2"), key("FK03", 1.1, "F3"), key("FK04", 1.1, "F4"), key("FK05", 1.1, "F5"), key("FK06", 1.1, "F6"), key("FK07", 1.1, "F7"), key("FK08", 1.1, "F8"), key("FK09", 1.1, "F9"), key("FK10", 1.1, "F10"), key("FK11", 1.1, "F11"), key("FK12", 1.1, "F12")],
    [key("TLDE"), key("AE01"), key("AE02"), key("AE03"), key("AE04"), key("AE05"), key("AE06"), key("AE07"), key("AE08"), key("AE09"), key("AE10"), key("AE11"), key("AE12"), key("BKSP", 2, "⌫")],
    [key("TAB", 1.5, "⇥"), key("AD01"), key("AD02"), key("AD03"), key("AD04"), key("AD05"), key("AD06"), key("AD07"), key("AD08"), key("AD09"), key("AD10"), key("AD11"), key("AD12"), key("BKSL", 1.5)],
    [key("CAPS", 1.8, "⇪"), key("AC01"), key("AC02"), key("AC03"), key("AC04"), key("AC05"), key("AC06"), key("AC07"), key("AC08"), key("AC09"), key("AC10"), key("AC11"), key("RTRN", 2.2, "↵")],
    [key("LFSH", 2.2, "⇧"), key("LSGT"), key("AB01"), key("AB02"), key("AB03"), key("AB04"), key("AB05"), key("AB06"), key("AB07"), key("AB08"), key("AB09"), key("AB10"), key("RTSH", 1.8, "⇧")],
    [key("LCTL", 1.2, "ctrl"), key("LWIN", 1.2, "super"), key("LALT", 1.2, "alt"), key("SPCE", 6), key("RALT", 1.2, "alt gr"), key("RWIN", 1.2, "super"), key("LEFT", 1, "←"), key("ARROWSTACK"), key("RGHT", 1, "→")]
  ]

  function key(id, units, name) { return { id: id, units: units || 1, name: name || "" } }

  function focusedScreen() {
    var wanted = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (String(Quickshell.screens[i].name) === wanted) return Quickshell.screens[i]
    return Quickshell.screens.length ? Quickshell.screens[0] : null
  }

  function toggle() {
    if (opened) { opened = false; return }
    targetScreen = focusedScreen()
    shifted = false
    altGr = false
    capsOn = false
    pendingDead = ""
    pendingDeadId = ""
    accentChoices = []
    accentKeyId = ""
    opened = true
    load()
  }

  onSignatureChanged: {
    pendingDead = ""
    pendingDeadId = ""
    accentChoices = []
    accentKeyId = ""
    if (opened) load()
  }

  function load() {
    if (!activeLayout) return
    if (keymapProc.running) { reloadPending = true; return }
    requestedSignature = signature
    keyLabels = ({})
    errorText = ""
    keymapProc.running = true
  }

  function displayLabel(spec) {
    if (spec.name) return spec.name
    var levels = keyLabels[spec.id] ? keyLabels[spec.id].labels : []
    var level = levelFor(spec)
    return levels[level] || levels[altGr ? 2 : 0] || levels[0] || ""
  }

  function levelFor(spec) {
    var entry = keyLabels[spec.id]
    var cased = !!entry && entry.labels[0].length === 1 && entry.labels[1].length === 1
      && entry.labels[0].toUpperCase() === entry.labels[1]
      && entry.labels[0].toLowerCase() !== entry.labels[0].toUpperCase()
    return (altGr ? 2 : 0) + ((shifted !== (capsOn && cased)) ? 1 : 0)
  }

  function alternateLabel(spec) {
    if (!/^(TLDE|AE\d\d|AD1[12]|BKSL|AC1[01]|LSGT|AB(08|09|10))$/.test(spec.id)) return ""
    var entry = keyLabels[spec.id]
    if (!entry) return ""
    var level = (altGr ? 2 : 0) + (levelFor(spec) % 2 === 0 ? 1 : 0)
    var other = entry.labels[level] || ""
    return other === displayLabel(spec) ? "" : other
  }

  function isDeadKey(spec) {
    var entry = keyLabels[spec.id]
    if (!entry) return false
    var level = levelFor(spec)
    if (!entry.labels[level]) level = altGr && entry.labels[2] ? 2 : 0
    var symbols = entry.keysyms[level] || []
    return symbols.length === 1 && symbols[0].indexOf("dead_") === 0
  }

  function toggleModifier(id) {
    if (id === "LFSH" || id === "RTSH") shifted = !shifted
    else if (id === "RALT") altGr = !altGr
  }

  function openAccents(spec, face) {
    var choices = Typing.accents(displayLabel(spec))
    if (!choices.length) return
    var point = face.mapToItem(card, 0, 0)
    var popupWidth = choices.length * Style.space(36) + (choices.length - 1) * Style.space(3)
      + Style.space(8)
    accentPopupX = Math.max(card.contentLeftInset,
      Math.min(point.x, card.width - card.contentRightInset - popupWidth))
    accentPopupY = Math.max(card.contentTopInset, point.y - Style.space(46))
    accentChoices = choices
    accentKeyId = spec.id
  }

  function queueType(args) {
    typeQueue = typeQueue.concat([args])
    startNextType()
  }

  function startNextType() {
    if (typeProc.running || typeQueue.length === 0) return
    activeCommand = typeQueue[0]
    typeQueue = typeQueue.slice(1)
    typeProc.running = true
  }

  function typeKey(spec) {
    if (spec.id === "CAPS") { capsOn = !capsOn; return }
    if (spec.id === "LFSH" || spec.id === "RTSH" || spec.id === "RALT") {
      toggleModifier(spec.id)
      return
    }
    var special = { ESC: "Escape", BKSP: "BackSpace", TAB: "Tab", RTRN: "Return", SPCE: "space", LEFT: "Left", UP: "Up", DOWN: "Down", RGHT: "Right" }
    if (/^FK\d\d$/.test(spec.id)) special[spec.id] = "F" + String(parseInt(spec.id.substring(2), 10))
    if (special[spec.id]) {
      if (pendingDead) {
        var spacing = Typing.spacing(pendingDead)
        if (spec.id !== "ESC" && spec.id !== "BKSP" && spacing)
          queueType(["wtype", "--", spacing])
        pendingDead = ""
        pendingDeadId = ""
        if (spec.id === "ESC" || spec.id === "BKSP" || spec.id === "SPCE") return
      }
      queueType(["wtype", "-k", special[spec.id]])
      return
    }
    if (spec.name || !keyLabels[spec.id]) return
    var entry = keyLabels[spec.id]
    var level = levelFor(spec)
    if (!entry.labels[level]) level = altGr && entry.labels[2] ? 2 : 0
    var symbols = entry.keysyms[level] || []
    if (symbols.length === 1 && symbols[0].indexOf("dead_") === 0) {
      if (pendingDead) {
        var previous = Typing.spacing(pendingDead)
        if (previous) queueType(["wtype", "--", previous])
      }
      pendingDead = symbols[0]
      pendingDeadId = spec.id
      return
    }
    var typed = entry.labels[level].replace(/◌/g, "")
    if (pendingDead) {
      var composed = Typing.compose(pendingDead, typed)
      if (composed === null) queueType(["wtype", "-k", pendingDead, "--", typed])
      else if (composed) queueType(["wtype", "--", composed])
      pendingDead = ""
      pendingDeadId = ""
      return
    }
    if (typed) queueType(["wtype", "--", typed])
  }

  Process {
    id: typeProc
    command: root.activeCommand
    onExited: root.startNextType()
  }

  Process {
    id: keymapProc
    command: ["python3", "-B", root.scriptPath,
      root.activeLayout ? root.activeLayout.layout : "",
      root.activeLayout ? root.activeLayout.variant : "",
      root.service.keyboardModel, root.service.keyboardOptions]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.requestedSignature !== root.signature) return
        try { root.keyLabels = JSON.parse(text) }
        catch (e) { root.errorText = "Could not read this keyboard layout" }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.requestedSignature === root.signature)
        root.errorText = "Could not read this keyboard layout"
      if (root.reloadPending) {
        root.reloadPending = false
        root.load()
      }
    }
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

    BorderSurface {
      id: card
      x: (panel.width - width) / 2
      y: (panel.height - height) / 2
      width: Math.min(parent.width - Style.space(24), Style.space(800))
      height: viewerColumn.implicitHeight + contentTopInset + contentBottomInset
      radius: Math.max(Style.cornerRadius, Style.space(12))
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
      padding: Style.spacing.panelPadding

      Column {
        id: viewerColumn
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(36)

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(48)
            height: Style.space(4)
            radius: height / 2
            color: Util.alpha(Color.menu.text, dragArea.pressed ? 0.7 : dragArea.containsMouse ? 0.5 : 0.32)
          }

          MouseArea {
            id: dragArea
            x: -card.contentLeftInset
            y: -card.contentTopInset
            width: card.width
            height: parent.height + card.contentTopInset
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: card
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 0
            drag.maximumX: panel.width - card.width
            drag.minimumY: 0
            drag.maximumY: panel.height - card.height
          }

          Rectangle {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(23)
            height: width
            radius: width / 2
            color: Util.alpha(Color.menu.text, 0.12)

            Text {
              anchors.centerIn: parent
              text: "×"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.opened = false
            }
          }

        }

        Column {
          width: parent.width
          spacing: root.gap

          Repeater {
            model: root.rows
            Row {
              required property var modelData
              required property int index
              width: parent.width
              spacing: root.gap
              readonly property real keyUnit: (width - root.gap * (modelData.length - 1))
                / modelData.reduce(function(total, spec) { return total + spec.units }, 0)

              Repeater {
                model: parent.modelData
                Item {
                  id: keySlot
                  required property var modelData
                  readonly property bool selected: (modelData.id === "LFSH" || modelData.id === "RTSH") && root.shifted
                    || modelData.id === "RALT" && root.altGr || modelData.id === "CAPS" && root.capsOn
                    || modelData.id === root.pendingDeadId
                  readonly property bool deadKey: root.isDeadKey(modelData)
                  readonly property string alternate: root.alternateLabel(modelData)
                  width: parent.keyUnit * modelData.units
                  height: parent.index === 0 ? Style.space(39) : Style.space(49)

                  Rectangle {
                    visible: modelData.id !== "ARROWSTACK"
                    x: 0
                    y: Style.space(2)
                    width: parent.width
                    height: parent.height - Style.space(2)
                    radius: Style.space(5)
                    color: Qt.darker(Color.menu.background, 1.4)
                  }

                  Rectangle {
                    id: keyFace
                    visible: modelData.id !== "ARROWSTACK"
                    width: parent.width
                    height: parent.height - Style.space(3)
                    radius: Style.space(5)
                    color: keySlot.selected ? Color.menu.selectedBackground : Util.alpha(Color.menu.text, 0.12)
                    border.width: keySlot.deadKey ? 2 : 1
                    border.color: keySlot.selected || keySlot.deadKey ? Color.menu.selectedText : Util.alpha(Color.menu.text, 0.55)
                  }

                  Text {
                    visible: modelData.id !== "ARROWSTACK"
                    anchors.centerIn: keyFace
                    anchors.horizontalCenterOffset: keySlot.alternate ? Style.space(6) : 0
                    anchors.verticalCenterOffset: keySlot.alternate ? Style.space(5) : 0
                    width: keyFace.width - Style.space(5)
                    text: root.displayLabel(modelData)
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: keySlot.selected || keySlot.deadKey ? Color.menu.selectedText : Color.menu.text
                    font.family: "Noto Sans"
                    font.pixelSize: modelData.name && modelData.name.length > 2 ? Style.font.body + 1 : Style.font.heading + 3
                  }

                  Text {
                    visible: modelData.id !== "ARROWSTACK" && keySlot.alternate.length > 0
                    anchors.left: keyFace.left
                    anchors.top: keyFace.top
                    anchors.leftMargin: Style.space(5)
                    anchors.topMargin: Style.space(2)
                    text: keySlot.alternate
                    textFormat: Text.PlainText
                    color: Util.alpha(Color.menu.text, 0.72)
                    font.family: "Noto Sans"
                    font.pixelSize: Math.max(9, Style.font.body - 2)
                  }

                  MouseArea {
                    anchors.fill: keyFace
                    visible: modelData.id !== "ARROWSTACK"
                    enabled: modelData.id === "CAPS" || modelData.id === "LFSH" || modelData.id === "RTSH" || modelData.id === "RALT"
                      || modelData.id === "ESC" || /^FK\d\d$/.test(modelData.id)
                      || modelData.id === "BKSP" || modelData.id === "TAB" || modelData.id === "RTRN"
                      || modelData.id === "SPCE" || modelData.id === "LEFT" || modelData.id === "UP"
                      || modelData.id === "DOWN" || modelData.id === "RGHT"
                      || !modelData.name && !!root.keyLabels[modelData.id]
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressAndHold: root.openAccents(modelData, keyFace)
                    onClicked: {
                      if (root.accentKeyId === modelData.id) return
                      root.accentChoices = []
                      root.accentKeyId = ""
                      root.typeKey(modelData)
                    }
                  }

                  Column {
                    visible: modelData.id === "ARROWSTACK"
                    width: parent.width
                    height: parent.height
                    spacing: Style.space(2)

                    Repeater {
                      model: ["UP", "DOWN"]
                      Rectangle {
                        required property string modelData
                        width: parent.width
                        height: (parent.height - parent.spacing) / 2
                        radius: Style.space(4)
                        color: Util.alpha(Color.menu.text, 0.12)
                        border.width: 1
                        border.color: Util.alpha(Color.menu.text, 0.55)

                        Text {
                          anchors.centerIn: parent
                          text: modelData === "UP" ? "↑" : "↓"
                          color: Color.menu.text
                          font.family: "Noto Sans"
                          font.pixelSize: Style.font.body
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.typeKey({ id: modelData })
                        }
                      }
                    }
                  }
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
              color: Util.alpha(Color.menu.text, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.menu.text, 0.55)

              Text {
                anchors.centerIn: parent
                text: modelData
                color: Color.menu.text
                font.family: "Noto Sans"
                font.pixelSize: Style.font.heading + 3
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.queueType(["wtype", "--", modelData])
                  root.accentChoices = []
                  root.accentKeyId = ""
                }
              }
            }
          }
        }
      }
    }
  }
}
