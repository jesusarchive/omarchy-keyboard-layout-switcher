import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Ctrl+Space switcher on the focused monitor. The card uses Omarchy's menu
// colors. Its layer grabs the keyboard to detect Ctrl release and repeated
// Space presses; Hyprland bindings only report key presses.
Item {
  id: root

  required property var service

  // The keyboard grab can start before the card becomes visible.
  property bool opened: false
  // A quick Ctrl+Space tap ends before the card is revealed.
  property bool revealed: false

  // Delay the card so a quick switch has no overlay.
  readonly property int switcherDelayMs: 250
  readonly property bool grabbing: opened
  // The service uses this timestamp to reject a duplicate binding call.
  property double lastKeyAt: 0

  function sawKeyRecently(ms) {
    return lastKeyAt > 0 && (Date.now() - lastKeyAt) < ms
  }

  // Close if the modifier release never arrives.
  readonly property int grabIdleMs: 5000

  signal advanceRequested()

  function isModifier(key) {
    return key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_Meta
      || key === Qt.Key_Shift || key === Qt.Key_Super_L || key === Qt.Key_Super_R
      || key === Qt.Key_AltGr
  }

  // Capture the monitor at open time so the card does not move mid-switch.
  property var targetScreen: null

  function focusedScreen() {
    var wanted = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name) === wanted) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  signal switcherClosed()

  // Assign once; a binding would move the card when focus changes.
  Component.onCompleted: targetScreen = focusedScreen()

  // Start the keyboard grab. The reveal timer controls card visibility.
  function show() {
    if (!opened) { targetScreen = focusedScreen(); lastKeyAt = 0 }
    opened = true
    if (!revealed) revealTimer.restart()
    hideTimer.restart()
  }

  function reveal() {
    revealTimer.stop()
    revealed = true
  }

  function close() {
    if (!opened) return
    revealTimer.stop()
    opened = false
    revealed = false
    switcherClosed()
  }

  Timer {
    id: hideTimer
    interval: root.grabIdleMs
    onTriggered: root.close()
  }

  Timer {
    id: revealTimer
    interval: root.switcherDelayMs
    onTriggered: root.reveal()
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    screen: root.targetScreen ? root.targetScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jesusarchive-keyboard-layout-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.grabbing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Let pointer events pass through to the window below.
    mask: Region {}

    Item {
      anchors.fill: parent
      focus: true

      // Space advances the list. Other non-modifier keys close the grab.
      Keys.onPressed: function(event) {
        root.lastKeyAt = Date.now()
        hideTimer.restart()
        if (event.key === Qt.Key_Space) {
          root.reveal()
          root.advanceRequested()
        }
        else if (!root.isModifier(event.key)) root.close()
        event.accepted = true
      }

      // Qt still includes Control in modifiers on release; inspect the key.
      Keys.onReleased: function(event) {
        root.lastKeyAt = Date.now()
        if (root.isModifier(event.key)) root.close()
        else hideTimer.restart()
        event.accepted = true
      }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.round(content.implicitWidth + card.contentLeftInset + card.contentRightInset)
      height: Math.round(content.implicitHeight + card.contentTopInset + card.contentBottomInset)
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      opacity: root.revealed ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      Item {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        implicitWidth: switcherColumn.implicitWidth
        implicitHeight: switcherColumn.implicitHeight

        Column {
          id: switcherColumn
          spacing: Style.spacing.sm

          readonly property real rowWidth: {
            var widest = Style.space(180)
            for (var i = 0; i < switcherRepeater.count; i++) {
              var item = switcherRepeater.itemAt(i)
              if (item) widest = Math.max(widest, item.labelWidth + Style.space(48))
            }
            return widest
          }

          Repeater {
            id: switcherRepeater
            model: root.service.layouts

            CursorSurface {
              required property var modelData
              readonly property bool selected: modelData.index === root.service.activeIndex
              readonly property real labelWidth: nameText.implicitWidth

              width: switcherColumn.rowWidth
              height: Math.max(Style.space(40), Style.font.heading + Style.space(20))
              radius: root.cornerRadius
              hasCursor: selected
              foreground: root.foreground

              // Show full layout names in the switcher.
              Text {
                id: nameText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.name
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }
          }
        }
      }
    }
  }
}
