import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

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
  readonly property string barAppearance: setting("barAppearance", "icon")
  readonly property bool showEmojis: setting("showEmojiAndSymbols", true) !== false
  readonly property bool showKeyboardViewer: setting("showKeyboardViewer", true) !== false
  readonly property string keyboardViewerGeometry: setting("keyboardViewerGeometry", "auto")
  readonly property bool showSourceNameMenuItem: setting("showSourceNameMenuItem", true) !== false
  readonly property bool showKeyboardSettings: setting("showKeyboardSettings", true) !== false
  readonly property string screenName: {
    var win = button.QsWindow.window
    return win && win.screen ? String(win.screen.name) : ""
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Menu rows in display order. Keyboard navigation skips separators.
  readonly property var rows: {
    if (layouts.length === 0) return []
    var out = layouts.map(function(s) {
      return { kind: "layout", index: s.index, label: s.name, glyph: s.glyph }
    })
    var actions = []
    if (showEmojis)
      actions.push({ kind: "action", action: "emoji", label: "Show Emojis", icon: "" })
    if (showKeyboardViewer)
      actions.push({ kind: "action", action: "viewer", label: svc && svc.viewerOpened ? "Hide Keyboard Viewer" : "Show Keyboard Viewer", icon: "" })
    if (actions.length > 0) {
      out.push({ kind: "separator" })
      out = out.concat(actions)
    }
    if (showSourceNameMenuItem) {
      out.push({ kind: "separator" })
      out.push({ kind: "action", action: "sourceName",
        label: showSourceName ? "Hide Input Source Name" : "Show Input Source Name" })
    }
    if (showKeyboardSettings) {
      out.push({ kind: "separator" })
      out.push({ kind: "action", action: "settings", label: "Open Keyboard Settings…" })
    }
    return out
  }

  property int cursorIndex: 0
  // Hide the initial highlight until keyboard navigation or hover begins.
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

  // The service owns the viewer; the bar widget supplies its shape setting.
  Binding {
    when: root.svc !== null
    target: root.svc
    property: "viewerGeometry"
    value: root.keyboardViewerGeometry
  }

  // Retry if the service loads after this widget.
  Timer {
    interval: 400
    repeat: true
    running: root.svc === null
    onTriggered: root.attachService()
  }

  onOpenedChanged: if (opened) {
    // Start keyboard navigation at the active layout.
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
      // Launch after closing: opening the picker in this frame makes the menu's
      // focus release dismiss it immediately.
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
  // Match the bar's open-panel mark to the painted icon and optional name.
  readonly property real openPanelIndicatorWidth: iconRow.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // ------------------------------------------------------------- bar icon

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: root.activeLayout !== null
    labelVisible: false
    fixedWidth: iconRow.implicitWidth + Style.space(12)
    // Both mouse buttons open the menu, like other bar widgets.
    onPressed: root.toggle()

    Row {
      id: iconRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        visible: root.opened
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      LayoutIcon {
        visible: !root.opened && root.barAppearance !== "bordered" && root.barAppearance !== "text"
        anchors.verticalCenter: parent.verticalCenter
        size: Style.space(15)
        glyph: root.activeLayout ? root.activeLayout.glyph : ""
        fill: root.foreground
        ink: root.bar && !root.bar.transparent ? root.bar.background : Color.background
        fontFamily: root.fontFamily
      }

      Rectangle {
        visible: !root.opened && root.barAppearance === "bordered"
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: borderedCode.implicitWidth + Style.space(8)
        implicitHeight: Style.space(19)
        radius: Style.space(4)
        color: "transparent"
        border.width: 1
        border.color: root.foreground

        Text {
          id: borderedCode
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.activeLayout ? root.activeLayout.glyph : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Text {
        visible: !root.opened && root.barAppearance === "text"
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.activeLayout ? root.activeLayout.glyph : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
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

  FontMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(6)
    readonly property real widestLabelWidth: root.rows.reduce(function(widest, row) {
      return Math.max(widest, labelMetrics.advanceWidth(row.label || ""))
    }, 0)
    readonly property bool hasActions: root.rows.some(function(row) { return row.kind === "action" })
    readonly property real labelReserve: Style.space(76)
    readonly property real horizontalInset: padding * 2 + Border.left(borderSpec) + Border.right(borderSpec)
    // Fit ordinary labels, but keep rare long XKB names from making a huge menu.
    contentWidth: panel.fittedContentWidth(Math.min(Style.space(340), Math.max(
      hasActions ? Style.space(260) : Style.space(200), widestLabelWidth + labelReserve + Style.space(8) + horizontalInset)))
    contentHeight: panel.fittedContentHeight(menuColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // Use Omarchy's shared panel key bindings.
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

    CursorSurface {
      id: rowItem
      readonly property var row: parent ? parent.rowData : null
      readonly property int rowIndex: parent ? parent.rowIndex : -1
      readonly property bool hot: root.cursorActive && root.cursorIndex === rowIndex
      readonly property bool checked: !!row && (row.kind === "layout" ? row.index === root.activeIndex : row.checked === true)
      readonly property color textColor: Color.popups.text

      implicitHeight: Style.space(28)
      implicitWidth: rowContent.implicitWidth + Style.space(22)
      hasCursor: hot
      foreground: Color.popups.text

      Row {
        id: rowContent
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(6)
        spacing: Style.space(6)

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
          width: Math.min(implicitWidth, Math.max(0, menuColumn.width - panel.labelReserve))
          elide: Text.ElideRight
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
