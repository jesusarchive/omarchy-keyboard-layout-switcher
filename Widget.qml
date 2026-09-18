import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar icon and the Input menu. The menu holds the source icon, a ✓ on the
// active source, Emoji & Symbols, Show Input Source Name and Keyboard Settings.
// Omarchy's panel components draw all of it.
Panel {
  id: root
  moduleName: "jesusarchive.language-switcher"
  manageIpc: false

  readonly property string pluginId: "jesusarchive.language-switcher"

  property QtObject svc: null
  readonly property var sources: svc ? svc.sources : []
  readonly property int activeIndex: svc ? svc.activeIndex : 0
  readonly property var activeSource: svc ? svc.activeSource : null
  readonly property bool hideWhenSingle: setting("hideWhenSingle", false) === true
  readonly property bool showSourceName: setting("showSourceName", false) === true
  readonly property string screenName: {
    var win = button.QsWindow.window
    return win && win.screen ? String(win.screen.name) : ""
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Menu rows in display order. Keyboard navigation steps over the separators.
  readonly property var rows: {
    var out = sources.map(function(s) {
      return { kind: "source", index: s.index, label: s.name, glyph: s.glyph }
    })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "emoji", label: "Show Emoji & Symbols", icon: "" })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "sourceName", label: "Show Input Source Name", checked: showSourceName })
    out.push({ kind: "separator" })
    out.push({ kind: "action", action: "settings", label: "Open Keyboard Settings…" })
    return out
  }

  property int cursorIndex: -1

  function attachService() {
    if (svc || !bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    var found = bar.shell.serviceFor(pluginId)
    if (!found) return
    svc = found
    svc.settings = root.settings
    svc.registerMenuHost(root)
  }

  onSettingsChanged: if (svc) svc.settings = settings
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
    cursorIndex = -1
    if (svc) svc.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function actionable(i) {
    return i >= 0 && i < rows.length && rows[i].kind !== "separator"
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    var i = cursorIndex
    if (i < 0) i = delta > 0 ? -1 : rows.length
    for (var step = 0; step < rows.length; step++) {
      i = (i + delta + rows.length) % rows.length
      if (actionable(i)) { cursorIndex = i; return }
    }
  }

  function activate(row) {
    if (!row || !svc) return
    if (row.kind === "source") {
      svc.select(row.index)
      close()
    } else if (row.action === "emoji") {
      close()
      // Straight to the host rather than out through `omarchy-shell`, which
      // would spawn a login shell and a qs client to reach this same process.
      // "{}" is the empty payload the CLI substitutes for an overlay.
      if (bar && bar.shell) bar.shell.toggle("omarchy.emojis", "{}")
    } else if (row.action === "sourceName") {
      setShowSourceName(!showSourceName)
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

  visible: svc !== null && sources.length > (hideWhenSingle ? 1 : 0)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------- bar icon

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: root.activeSource !== null
    labelVisible: false
    fixedWidth: iconRow.implicitWidth + Style.space(12)
    tooltipText: root.opened || !root.activeSource ? "" : root.activeSource.name
    // Either button opens the menu. A right click used to switch straight to
    // the next source, which meant the same gesture did different things here
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

      SourceIcon {
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(15)
        glyph: root.activeSource ? root.activeSource.glyph : ""
        fill: root.foreground
        ink: root.bar && !root.bar.transparent ? root.bar.background : Color.background
        fontFamily: root.fontFamily
      }

      Text {
        visible: root.showSourceName && root.activeSource !== null
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.activeSource ? root.activeSource.name : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // ----------------------------------------------------------- input menu

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

      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: {
        if (root.actionable(root.cursorIndex)) root.activate(root.rows[root.cursorIndex])
        else root.moveCursor(1)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "j") root.moveCursor(1)
        else if (t === "k") root.moveCursor(-1)
        else {
          // Typing the first letter of a source name picks it, the way typing a
          // menu item's name does. `j` and `k` are navigation, so they never match.
          var lower = t.toLowerCase()
          for (var i = 0; i < root.rows.length; i++) {
            var row = root.rows[i]
            if (row.kind === "source" && row.label.toLowerCase().charAt(0) === lower) {
              root.cursorIndex = i
              return
            }
          }
        }
      }

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
      readonly property bool hot: root.cursorIndex === rowIndex
      readonly property bool checked: !!row && (row.kind === "source" ? row.index === root.activeIndex : row.checked === true)
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

        // The ✓ column, blank on every row but the active source.
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
          visible: !!rowItem.row && (rowItem.row.kind === "source" || !!rowItem.row.icon)
          width: Style.space(22)
          height: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter

          SourceIcon {
            visible: !!rowItem.row && rowItem.row.kind === "source"
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
        onEntered: root.cursorIndex = rowItem.rowIndex
        onClicked: root.activate(rowItem.row)
      }
    }
  }
}
