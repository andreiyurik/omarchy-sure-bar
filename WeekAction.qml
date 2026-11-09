pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// One action for the week: something you control, unlike whether a client says yes.
Column {
  id: root
  property var service: null
  readonly property var action: service && service.game ? service.game.action : null
  readonly property bool finished: !!action && action.done >= action.target
  signal commandRequested(string text)
  spacing: Style.space(6)

  Item {
    width: parent.width; height: Math.max(title.implicitHeight, controls.implicitHeight)
    Ui.PanelSectionHeader {
      id: title
      anchors.verticalCenter: parent.verticalCenter
      foreground: Commons.Color.popups.text
      text: root.service ? root.service.t("week.title") : ""
    }
    Row {
      id: controls
      anchors.right: parent.right
      visible: !!root.action
      spacing: Style.space(2)
      Ui.PanelActionButton {
        visible: !!root.action && !root.action.demo
        iconText: "󰍴"; foreground: Commons.Color.popups.text
        enabled: !!root.action && root.action.done > 0
        tooltipText: root.service ? root.service.t("week.minus") : ""
        onClicked: root.service.bumpAction(-1)
      }
      Ui.PanelActionButton {
        visible: !!root.action && !root.action.demo
        iconText: "󰐕"; foreground: Commons.Color.popups.text
        tooltipText: root.service ? root.service.t("week.plus") : ""
        onClicked: root.service.bumpAction(1)
      }
      Ui.PanelActionButton {
        iconText: "󰏫"; foreground: Commons.Color.popups.text
        tooltipText: root.service ? root.service.t("week.edit") : ""
        onClicked: root.commandRequested(root.service.t("command.week-word") + " " + root.action.target + " " + root.action.text)
      }
    }
  }

  Item {
    width: parent.width; height: name.implicitHeight
    visible: !!root.action
    Txt {
      id: name
      width: parent.width - count.implicitWidth - Style.space(12)
      text: root.action ? root.action.text : ""
    }
    Txt {
      id: count
      anchors.right: parent.right
      font.bold: true
      color: root.finished ? Commons.Color.accent : Commons.Color.popups.text
      text: root.action ? (root.finished ? "✓ " : "") + root.action.done + " / " + root.action.target : ""
    }
  }

  Row {
    visible: !!root.action && root.action.target <= 20
    spacing: Style.space(4)
    Repeater {
      model: root.action && root.action.target <= 20 ? root.action.target : 0
      Rectangle {
        required property int index
        width: Style.space(10); height: width; radius: width / 2
        color: root.action && index < root.action.done ? Commons.Color.accent : "transparent"
        border.width: root.action && index < root.action.done ? 0 : 1
        border.color: Util.alpha(Commons.Color.popups.text, 0.3)
      }
    }
  }
  Meter {
    width: parent.width
    visible: !!root.action && root.action.target > 20
    ratio: root.action ? root.action.done / root.action.target : 0
  }

  Hint {
    width: parent.width
    visible: !root.action
    wrapMode: Text.Wrap
    text: root.service ? root.service.t("week.empty") : ""
  }
  Ui.Button {
    visible: !root.action
    foreground: Commons.Color.popups.text
    bordered: true
    text: root.service ? root.service.t("week.set") : ""
    onClicked: root.commandRequested(root.service.t("command.week-word") + " ")
  }
}
