import QtQuick
import qs.Commons
import qs.Commons as Commons

// One line for the whole ladder: reached, next, still ahead.
Item {
  id: root
  property var steps: []
  property real segment: 0
  property int hovered: -1
  readonly property int count: steps.length
  readonly property real dot: Style.space(10)
  readonly property real gap: count > 1 ? (width - dot) / (count - 1) : 0
  readonly property int reached: steps.filter(function(step) { return step.done }).length
  readonly property real progress: reached <= 0 ? segment * gap : Math.min(width - dot, (reached - 1) * gap + (reached < count ? segment * gap : 0))
  implicitHeight: Style.space(22)

  Rectangle {
    x: root.dot / 2; anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, root.width - root.dot); height: Style.space(2)
    color: Util.alpha(Commons.Color.popups.text, 0.18)
  }
  Rectangle {
    x: root.dot / 2; anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, root.progress); height: Style.space(2)
    color: Commons.Color.accent
    Behavior on width { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
  }
  Repeater {
    model: root.steps
    Item {
      id: stepItem
      required property var modelData
      required property int index
      readonly property bool isNext: index === root.reached
      x: index * root.gap + root.dot / 2 - width / 2
      width: Style.space(22); height: parent.height
      Rectangle {
        anchors.centerIn: parent
        width: root.hovered === stepItem.index ? root.dot + Style.space(2) : root.dot
        height: width
        radius: width / 2
        color: stepItem.modelData.done ? Commons.Color.accent : Commons.Color.popups.background
        border.width: stepItem.isNext ? Style.space(2) : stepItem.modelData.done ? 0 : 1
        border.color: stepItem.isNext ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.3)
      }
      MouseArea {
        anchors.fill: parent; hoverEnabled: true
        onEntered: root.hovered = stepItem.index
        onExited: if (root.hovered === stepItem.index) root.hovered = -1
      }
    }
  }
}
