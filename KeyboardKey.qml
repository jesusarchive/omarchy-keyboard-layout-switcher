import QtQuick
import QtQuick.Shapes
import qs.Commons

// One key, including its face and pointer gestures. The viewer owns typing.
Item {
  id: cap
  required property var geometry
  required property real pitch
  property bool live: true
  property bool latched: false
  property bool locked: false
  property bool armed: false
  property bool layoutKey: false
  property string label: ""
  property string alternate: ""
  property bool deadKey: false

  signal keyPressed()
  signal keyReleased()
  signal keyClicked()
  signal keyHeld(var mouse)

  readonly property bool isL: geometry.cutW > 0
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

  // Latched modifiers have an accent outline. Locked modifiers
  // have an accent fill. Dead keys keep the outline.
  readonly property color faceColor: !live ? Util.alpha(Color.menu.text, 0.04)
    : locked ? Util.alpha(Color.accent, 0.38)
    : down ? Util.alpha(Color.menu.text, 0.34)
    : armed ? Util.alpha(Color.accent, 0.22)
    : hovered ? Util.alpha(Color.menu.text, 0.2)
    : Util.alpha(Color.menu.text, 0.1)
  readonly property color edgeColor: latched || armed ? Color.accent
    : hovered || down ? Util.alpha(Color.menu.text, 0.9)
    : deadKey ? Color.accent
    : Util.alpha(Color.menu.text, live ? 0.32 : 0.14)
  readonly property bool strongEdge: hovered || down || latched || armed || deadKey
  readonly property color inkColor: Util.alpha(Color.menu.text, live ? 1 : 0.3)

  x: geometry.x
  y: geometry.y
  width: geometry.w
  height: geometry.h

  KeyFace {
    id: face
    anchors.fill: parent
    lShape: cap.isL
    cutW: cap.geometry.cutW
    cutY: cap.geometry.cutY
    fill: cap.faceColor
    edge: cap.edgeColor
    edgeWidth: cap.strongEdge ? 1.5 : 1
  }

  Item {
    // The L-shaped Enter centers its label on the full-height column.
    x: cap.isL ? cap.geometry.cutW : 0
    width: parent.width - x
    height: parent.height

    Text {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: cap.alternate ? cap.pitch * 0.1 : 0
      anchors.verticalCenterOffset: cap.alternate ? cap.pitch * 0.08 : 0
      width: parent.width - Style.space(4)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: cap.label
      textFormat: Text.PlainText
      color: cap.inkColor
      font.family: "Noto Sans"
      font.pixelSize: Math.max(8, Math.round(cap.pitch * (cap.layoutKey ? 0.36 : cap.label.length > 2 ? 0.22 : 0.3)))
    }

    Text {
      visible: cap.alternate.length > 0
      x: Math.round(cap.pitch * 0.1)
      y: Math.round(cap.pitch * 0.04)
      text: cap.alternate
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.65)
      font.family: "Noto Sans"
      font.pixelSize: Math.max(8, Math.round(cap.pitch * 0.22))
    }
  }

  Repeater {
    id: areas
    model: cap.geometry.rects

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
        if (pressed) cap.keyPressed()
        else cap.keyReleased()
      }
      onCanceled: cap.keyReleased()
      onPressAndHold: function(mouse) { cap.keyHeld(mouse) }
      onClicked: cap.keyClicked()
      // Qt suppresses onClicked for the second click. Repeating
      // keys already act on press; other keys need this second act.
      onDoubleClicked: cap.keyClicked()
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
