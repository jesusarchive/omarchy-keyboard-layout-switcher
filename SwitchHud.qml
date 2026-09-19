import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The two overlays that report an input source change:
//  - switcher: the Ctrl+Space list of sources, each with its icon and name,
//    current one boxed
//  - indicator: a small badge with the new source, plus ⇪ when Caps Lock is on
// This follows Omarchy's own overlays (emojis, clipboard, reminders). It is a
// full-screen layer holding a centred card that draws from the [menu] surface
// tokens. There is no scrim and no input, because the card only reports.
//
// The layer has no screen binding, so Quickshell places it on one output and
// leaves it there. Omarchy's OSD does the same. Bind `screen` here if the card
// should ever follow the focused monitor the way the Input menu does.
Item {
  id: root

  required property var service

  property string mode: ""
  property bool opened: false
  readonly property bool switcherOpen: opened && mode === "switcher"

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

  function show(nextMode) {
    if (opened && mode !== nextMode && mode === "switcher") switcherClosed()
    mode = nextMode
    opened = true
    hideTimer.interval = service.hudTimeoutMs
    hideTimer.restart()
  }

  function close() {
    if (!opened) return
    var wasSwitcher = mode === "switcher"
    opened = false
    if (wasSwitcher) switcherClosed()
  }

  Timer {
    id: hideTimer
    onTriggered: root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened || card.opacity > 0
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
        implicitWidth: root.mode === "switcher" ? switcherColumn.implicitWidth : indicatorRow.implicitWidth
        implicitHeight: root.mode === "switcher" ? switcherColumn.implicitHeight : indicatorRow.implicitHeight

        // ------------------------------------------------------ switcher

        Column {
          id: switcherColumn
          visible: root.mode === "switcher"
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
              id: switcherRow
              required property var modelData
              readonly property bool current: modelData.index === root.service.activeIndex
              readonly property real labelWidth: rowContent.implicitWidth

              width: switcherColumn.rowWidth
              height: Math.max(Style.space(40), Style.font.heading + Style.space(20))
              radius: root.cornerRadius
              color: current ? root.selectedBackground : "transparent"
              borderSpec: current ? root.selectedBorderSpec : Border.none()

              // The letters belong on every row. Without them the switcher is
              // the only one of the three surfaces that names a source without
              // showing the icon the bar and the indicator both draw.
              Row {
                id: rowContent
                anchors.centerIn: parent
                spacing: Style.spacing.md

                SourceIcon {
                  anchors.verticalCenter: parent.verticalCenter
                  size: Style.font.heading
                  glyph: switcherRow.modelData.glyph
                  fill: switcherRow.current ? root.selectedText : root.foreground
                  ink: switcherRow.current ? root.selectedBackground : root.background
                  fontFamily: root.fontFamily
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: switcherRow.modelData.name
                  color: switcherRow.current ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                }
              }
            }
          }
        }

        // ----------------------------------------------------- indicator

        Row {
          id: indicatorRow
          visible: root.mode === "indicator"
          spacing: Style.spacing.md

          SourceIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: Style.font.displayLarge
            glyph: root.service.activeSource ? root.service.activeSource.glyph : ""
            fill: root.selectedText
            ink: root.background
            fontFamily: root.fontFamily
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.service.activeSource ? root.service.activeSource.name : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            visible: root.service.capsLock
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "⇪"
            color: root.selectedText
            font.family: root.fontFamily
            font.bold: true
            font.pixelSize: Style.font.heading
          }
        }
      }
    }
  }
}
