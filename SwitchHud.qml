import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The Ctrl+Space switcher: a list of source names with the current one boxed.
// This follows Omarchy's own overlays (emojis, clipboard, reminders). It is a
// full-screen layer holding a centred card that draws from the [menu] surface
// tokens. There is no scrim and no input, because the card only reports.
//
// A menu pick and a scripted switch show nothing. The bar badge already names
// the source, and it is the thing the reader clicked or typed at.
//
// The card lands on the monitor that has focus, the same one `toggleMenu`
// opens the Input menu on. Omarchy's OSD leaves this unbound and stays put,
// which on two monitors means reading a switch on the screen you are not
// typing on.
Item {
  id: root

  required property var service

  property bool opened: false

  // The output the card sits on. Captured when it opens rather than bound to
  // the focused monitor, so moving focus mid-switch cannot make a card that is
  // already on screen jump to another monitor.
  property var targetScreen: null

  function focusedScreen() {
    var wanted = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : ""
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].name) === wanted) return list[i]
    }
    return list.length > 0 ? list[0] : null
  }

  // Same tokens as the Omarchy menu, so themes that style it style this.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  signal switcherClosed()

  // Assigned, not bound. A binding on focusedScreen() would follow the focused
  // monitor and move a card that is already up.
  Component.onCompleted: targetScreen = focusedScreen()

  function show() {
    if (!opened) targetScreen = focusedScreen()
    opened = true
    hideTimer.interval = service.hudTimeoutMs
    hideTimer.restart()
  }

  function close() {
    if (!opened) return
    opened = false
    switcherClosed()
  }

  Timer {
    id: hideTimer
    onTriggered: root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
    screen: root.targetScreen ? root.targetScreen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "jesusarchive-language-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The card only reports, so it must never take a click from the window
    // underneath it.
    mask: Region {}

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.round(content.implicitWidth + card.contentLeftInset + card.contentRightInset)
      height: Math.round(content.implicitHeight + card.contentTopInset + card.contentBottomInset)
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin
      opacity: root.opened ? 1 : 0

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
            model: root.service.sources

            BorderSurface {
              required property var modelData
              readonly property bool current: modelData.index === root.service.activeIndex
              readonly property real labelWidth: nameText.implicitWidth

              width: switcherColumn.rowWidth
              height: Math.max(Style.space(40), Style.font.heading + Style.space(20))
              radius: root.cornerRadius
              color: current ? root.selectedBackground : "transparent"
              borderSpec: current ? root.selectedBorderSpec : Border.none()

              // The name alone. The icon belongs on the bar, where one source
              // has to be read at a glance. A list is read by reading it.
              Text {
                id: nameText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.name
                color: parent.current ? root.selectedText : root.foreground
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
