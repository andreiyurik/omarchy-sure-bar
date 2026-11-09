import QtQuick
import qs.Commons
import qs.Commons as Commons

// A thin bar with optional ticks: [{ratio, color}]. Ticks mark a comparison on the same scale.
Item {
  id: root
  property real ratio: 0
  property color fill: Commons.Color.accent
  property var ticks: []
  implicitHeight: Style.space(14)

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Style.space(6)
    radius: height / 2
    color: Util.alpha(Commons.Color.popups.text, 0.14)
    Rectangle {
      width: Math.max(ratio_ > 0 ? height : 0, parent.width * ratio_)
      height: parent.height
      radius: parent.radius
      color: root.fill
      readonly property real ratio_: Math.max(0, Math.min(1, root.ratio))
      Behavior on width { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
    }
  }
  Repeater {
    model: root.ticks
    Rectangle {
      required property var modelData
      x: Math.round(root.width * Math.max(0, Math.min(1, modelData.ratio))) - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(2)
      height: root.height
      radius: 1
      color: modelData.color
      border.width: 0
    }
  }
}
