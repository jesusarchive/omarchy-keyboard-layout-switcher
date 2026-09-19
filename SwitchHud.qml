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
// While the card is up it takes the keyboard, so it can watch for the modifier
// coming back up and close on that rather than on a timer. A Hyprland bind only
// ever reports the press, but a layer surface with exclusive focus is handed
// the Key_Control release. The card owns the Space key for as long as it holds
// the keyboard, so a bind that still reaches the service is ignored there.
//
// The card lands on the monitor that has focus, the same one `toggleMenu`
// opens the Input menu on. Omarchy's OSD leaves this unbound and stays put,
// which on two monitors means reading a switch on the screen you are not
// typing on.
Item {
  id: root

  required property var service

  property bool opened: false

  // Turned off by `holdToCycle`, which falls the whole thing back to the timer.
  property bool holdToCycle: true
  readonly property bool grabbing: opened && holdToCycle
  // When a key last reached the card, as milliseconds since the epoch. The
  // service reads it to tell its own duplicate from a real press: a bind that
  // fires for the same Space lands a shell and a qs client later, so it is the
  // one that arrives just after a key. A bind firing with no key before it is
  // the only signal there is, and has to be acted on.
  property double lastKeyAt: 0

  function sawKeyRecently(ms) {
    return lastKeyAt > 0 && (Date.now() - lastKeyAt) < ms
  }

  // How long the card waits with the keyboard and nothing arriving. Only a
  // release that never came can get this far, so it is a safety net, not the
  // mechanism.
  readonly property int grabIdleMs: 5000

  signal advanceRequested()

  function isModifier(key) {
    return key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_Meta
      || key === Qt.Key_Shift || key === Qt.Key_Super_L || key === Qt.Key_Super_R
      || key === Qt.Key_AltGr
  }

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
    if (!opened) { targetScreen = focusedScreen(); lastKeyAt = 0 }
    opened = true
    hideTimer.interval = grabbing ? grabIdleMs : service.hudTimeoutMs
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
    WlrLayershell.keyboardFocus: root.grabbing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The card only reports, so it must never take a click from the window
    // underneath it. The keyboard is a different matter; see the grab above.
    mask: Region {}

    Item {
      anchors.fill: parent
      focus: true

      // Space walks the list. Anything else means the reader has moved on, so
      // give the keyboard straight back rather than swallowing their typing.
      Keys.onPressed: function(event) {
        root.lastKeyAt = Date.now()
        hideTimer.restart()
        if (event.key === Qt.Key_Space) root.advanceRequested()
        else if (!root.isModifier(event.key)) root.close()
        event.accepted = true
      }

      // The release the whole grab exists for. Qt still reports Control in
      // `modifiers` here, so the key itself is what to read.
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
