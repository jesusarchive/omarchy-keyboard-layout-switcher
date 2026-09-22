import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar icon and the layouts menu. The menu holds the layout icon, a ✓ on the
// active layout, Emoji & Symbols, the name toggle and Keyboard Settings.
// Omarchy's panel components draw all of it.
Panel {
  id: root
  moduleName: "jesusarchive.keyboard-layout-switcher"
  manageIpc: false

  readonly property string pluginId: "jesusarchive.keyboard-layout-switcher"

  property QtObject svc: null
  readonly property var layouts: svc ? svc.layouts : []
  readonly property int activeIndex: svc ? svc.activeIndex : 0
  readonly property var activeLayout: svc ? svc.activeLayout : null
  readonly property bool showSourceName: setting("showSourceName", false) === true
  readonly property string screenName: {
    var win = button.QsWindow.window
    return win && win.screen ? String(win.screen.name) : ""
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Menu rows in display order. Keyboard navigation steps over the separators.
  readonly property var rows: {
    var out = layouts.map(function(s) {
      return { kind: "layout", index: s.index, label: s.name, glyph: s.glyph }
    })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "emoji", label: "Show Emoji & Symbols", icon: "" })
    out.push({ kind: "action", action: "viewer", label: svc && svc.viewerOpened ? "Hide Keyboard Viewer" : "Show Keyboard Viewer", icon: "" })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "sourceName", label: "Show Input Source Name", checked: showSourceName })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "settings", label: "Open Keyboard Settings…" })
    return out
  }

  property int cursorIndex: 0
  // Omarchy's panels keep the highlight hidden until a key asks for it, then
  // the first press only reveals it where it already sits. Hovering a row
  // reveals it too. Closing hides it again.
  property bool cursorActive: false

  function attachService() {
    if (svc || !bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    var found = bar.shell.serviceFor(pluginId)
    if (!found) return
    svc = found
    svc.registerMenuHost(root)
  }

  onBarChanged: attachService()
  Component.onCompleted: attachService()
  Component.onDestruction: if (svc) svc.unregisterMenuHost(root)

  // The service loads alongside the widget, and a plugin reload rebuilds it,
  // so keep looking until it answers. A destroyed one reads back as null.
  Timer {
    interval: 400
    repeat: true
    running: root.svc === null
    onTriggered: root.attachService()
  }

  onOpenedChanged: if (opened) {
    // Open on the active layout, so the first j or k moves from where the
    // reader is rather than from the top of the menu.
    cursorIndex = actionable(activeIndex) ? activeIndex : 0
    cursorActive = false
    if (svc) svc.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function actionable(i) {
    return i >= 0 && i < rows.length && rows[i].kind !== "separator"
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    var i = cursorIndex
    for (var step = 0; step < rows.length; step++) {
      i = (i + delta + rows.length) % rows.length
      if (actionable(i)) { cursorIndex = i; return }
    }
  }

  function activate(row) {
    if (!row || !svc) return
    if (row.kind === "layout") {
      svc.select(row.index)
      close()
    } else if (row.action === "emoji") {
      close()
      // Out through `omarchy-shell` rather than straight to the host. Calling
      // the host here summons the picker in the same frame this menu closes,
      // and this menu handing the keyboard back dismisses the picker again the
      // moment it appears. Spawning a process puts the summon a few hundred
      // milliseconds later, by which time there is nothing left to dismiss it.
      if (bar) bar.run("omarchy-shell shell toggle omarchy.emojis")
    } else if (row.action === "sourceName") {
      close()
      setShowSourceName(!showSourceName)
    } else if (row.action === "viewer") {
      close()
      svc.toggleViewer()
    } else if (row.action === "settings") {
      close()
      if (bar) bar.run("omarchy-launch-editor " + Util.shellQuote(Quickshell.env("HOME") + "/.config/hypr/input.lua"))
    }
  }

  function setShowSourceName(value) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var next = {}
    for (var k in settings) next[k] = settings[k]
    next.showSourceName = value
    bar.shell.updateEntryInline(pluginId, next)
  }

  visible: svc !== null && layouts.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- bar icon

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: root.activeLayout !== null
    labelVisible: false
    fixedWidth: iconRow.implicitWidth + Style.space(12)
    tooltipText: root.opened || !root.activeLayout ? "" : root.activeLayout.name
    // Either button opens the menu. A right click used to switch straight to
    // the next layout, which meant the same gesture did different things here
    // and on every other bar widget.
    onPressed: root.toggle()

    // The pressed-in look the bar item takes on while its menu is open.
    Rectangle {
      anchors.centerIn: parent
      width: iconRow.implicitWidth + Style.space(8)
      height: Math.min(parent.height - Style.space(4), Style.space(22))
      radius: Math.min(Style.cornerRadius, height / 2)
      color: Util.alpha(root.foreground, 0.16)
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Row {
      id: iconRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      LayoutIcon {
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(15)
        glyph: root.activeLayout ? root.activeLayout.glyph : ""
        fill: root.foreground
        ink: root.bar && !root.bar.transparent ? root.bar.background : Color.background
        fontFamily: root.fontFamily
      }

      Text {
        visible: root.showSourceName && root.activeLayout !== null
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.activeLayout ? root.activeLayout.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // --------------------------------------------------------- layouts menu

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(6)
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // PanelKeyCatcher owns the key map, so h/j/k/l, the arrows, Enter,
      // Space, Tab and Esc behave here exactly as in every Omarchy panel.
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (root.actionable(root.cursorIndex)) root.activate(root.rows[root.cursorIndex])
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: menuColumn
        width: parent.width

        Repeater {
          id: menuRepeater
          model: root.rows

          Loader {
            required property var modelData
            required property int index
            width: menuColumn.width
            sourceComponent: modelData.kind === "separator" ? separatorRow : menuRow

            property var rowData: modelData
            property int rowIndex: index
          }
        }
      }
    }
  }

  Component {
    id: separatorRow

    Item {
      implicitHeight: Style.space(9)
      PanelSeparator {
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(8)
        width: parent.width - Style.space(16)
        foreground: Color.popups.text
      }
    }
  }

  Component {
    id: menuRow

    Item {
      id: rowItem
      readonly property var row: parent ? parent.rowData : null
      readonly property int rowIndex: parent ? parent.rowIndex : -1
      readonly property bool hot: root.cursorActive && root.cursorIndex === rowIndex
      readonly property bool checked: !!row && (row.kind === "layout" ? row.index === root.activeIndex : row.checked === true)
      readonly property color textColor: hot ? Color.menu.selectedText : Color.popups.text

      implicitHeight: Style.space(28)
      implicitWidth: rowContent.implicitWidth + Style.space(22)

      Rectangle {
        anchors.fill: parent
        radius: Math.min(Style.cornerRadius, height / 2)
        color: rowItem.hot ? Color.menu.selectedBackground : "transparent"
        border.width: rowItem.hot ? 1 : 0
        border.color: Color.menu.selectedBorder
      }

      Row {
        id: rowContent
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(6)
        spacing: Style.space(6)

        // The ✓ column, blank on every row but the active layout.
        Text {
          width: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: rowItem.checked ? "✓" : ""
          color: rowItem.textColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Item {
          visible: !!rowItem.row && (rowItem.row.kind === "layout" || !!rowItem.row.icon)
          width: Style.space(22)
          height: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter

          LayoutIcon {
            visible: !!rowItem.row && rowItem.row.kind === "layout"
            anchors.centerIn: parent
            size: Style.space(17)
            glyph: rowItem.row && rowItem.row.glyph ? rowItem.row.glyph : ""
            fill: rowItem.textColor
            ink: Color.popups.background
            fontFamily: root.fontFamily
          }

          Text {
            visible: !!rowItem.row && !!rowItem.row.icon
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: rowItem.row && rowItem.row.icon ? rowItem.row.icon : ""
            color: rowItem.textColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: rowItem.row ? rowItem.row.label : ""
          color: rowItem.textColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorIndex = rowItem.rowIndex
        }
        onClicked: root.activate(rowItem.row)
      }
    }
  }
}
