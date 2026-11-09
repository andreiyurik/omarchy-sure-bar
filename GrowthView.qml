pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Column {
  id: root
  property var service: null
  readonly property var game: service ? service.game : null
  readonly property real recordAmount: game && game.record ? game.record.amount : 0
  readonly property var goal: game ? game.goal : null
  readonly property real scale: goal ? Math.max(goal.target, goal.current) * (goal.reached ? 1.04 : 1) : game ? Math.max(1, game.current, game.prevSame, recordAmount) * 1.04 : 1
  readonly property bool racing: !!game && (game.prevSame > 0 || recordAmount > 0)
  readonly property color prevTick: Util.alpha(Commons.Color.popups.text, 0.9)
  readonly property color recordTick: Util.alpha(Commons.Color.popups.text, 0.45)
  readonly property color stageTick: Util.alpha(Commons.Color.popups.text, 0.3)
  readonly property var extras: game ? game.achieved.filter(function(win) { return win.kind !== "revenue" }) : []
  readonly property var hoveredStep: ladder.hovered >= 0 && game ? game.ladder[ladder.hovered] : null
  signal commandRequested(string text)
  spacing: Style.space(14)

  function goalWord() { return service.t("command.goal-word") + " " }
  // Whichever is smaller reads as faster progress: done so far, then what is left.
  function goalFigure() {
    if (goal.reached) return service.signed(goal.over)
    return goal.halfway ? service.money(goal.remaining) : service.number(goal.percent, 0) + "%"
  }
  function goalCaption() {
    if (goal.reached) return service.t("goal.over")
    return service.t(goal.halfway ? "goal.to" : "goal.of").arg(service.money(goal.target))
  }
  function goalTicks() {
    var out = goal.stages.filter(function(stage) { return stage < goal.target }).map(function(stage) { return {ratio: stage / root.scale, color: root.stageTick} })
    if (goal.reached) out.push({ratio: goal.target / root.scale, color: root.prevTick})
    else out.push({ratio: goal.paceAmount / root.scale, color: root.prevTick})
    return out
  }

  function stepText(step) {
    var amount = service.money(step.target)
    if (!step.done) return service.t("growth.step-open").arg(amount)
    return service.t("growth.step-done").arg(amount).arg(service.monthOf(step.date) + " " + step.date.slice(0, 4))
  }

  MonthReview {
    width: parent.width
    visible: !!root.game && !!root.game.review
    service: root.service
    onChangeRequested: root.commandRequested(root.goalWord() + Math.round(root.game.review.target))
  }

  // Headline: this month's revenue against the goal, or against the past when there is none.
  Column {
    width: parent.width
    spacing: Style.space(4)
    Item {
      width: parent.width; height: head.implicitHeight
      Ui.PanelSectionHeader {
        id: head
        foreground: Commons.Color.popups.text
        text: root.game ? root.service.t(root.goal ? "goal.title" : "growth.revenue").arg(root.service.monthName(root.game.monthIndex)) : ""
      }
      Ui.PanelActionButton {
        id: editGoal
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        visible: !!root.goal
        iconText: "󰏫"; foreground: Commons.Color.popups.text
        tooltipText: root.service ? root.service.t("goal.edit") : ""
        onClicked: root.commandRequested(root.goalWord() + Math.round(root.goal.target))
      }
      Hint {
        anchors.right: editGoal.visible ? editGoal.left : parent.right; anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: editGoal.visible ? Style.space(4) : 0
        text: root.game ? root.service.t("growth.day").arg(root.game.day).arg(root.game.daysInMonth) : ""
      }
    }
    Item {
      width: parent.width; height: hero.implicitHeight
      Txt {
        id: hero
        width: parent.width - Math.max(delta.implicitWidth, 0) - Style.space(12)
        font.pixelSize: Style.font.displayLarge
        font.bold: true
        text: root.game ? root.service.money(root.game.current) : ""
      }
      Column {
        id: delta
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(3)
        visible: !!root.goal || (!!root.game && (root.game.delta !== null || root.game.isRecord))
        spacing: 0
        Txt {
          anchors.right: parent.right
          font.pixelSize: Style.font.title
          font.bold: true
          color: !!root.goal || !root.game || root.game.delta === null || root.game.delta >= 0 ? Commons.Color.accent : Commons.Color.popups.text
          text: {
            var g = root.game
            if (!g) return ""
            if (root.goal) return root.goalFigure()
            if (g.isRecord) return "★ " + root.service.t("growth.record-badge")
            return (g.delta >= 0 ? "▲ " : "▼ ") + root.service.number(Math.abs(g.delta), 0) + "%"
          }
        }
        Hint {
          anchors.right: parent.right
          visible: !!root.goal || (!!root.game && root.game.delta !== null)
          text: !root.service ? "" : root.goal ? root.goalCaption() : root.service.t("growth.vs-last")
        }
      }
    }
    Meter {
      width: parent.width
      visible: root.racing || !!root.goal
      ratio: root.game ? root.game.current / root.scale : 0
      ticks: {
        var g = root.game, out = []
        if (!g) return out
        if (root.goal) return root.goalTicks()
        if (g.prevSame > 0) out.push({ratio: g.prevSame / root.scale, color: root.prevTick})
        if (g.record) out.push({ratio: g.record.amount / root.scale, color: root.recordTick})
        return out
      }
    }
    // The next stage on the left; the even-pace tick is explained on the right and is never a warning.
    Item {
      width: parent.width; height: stageLine.implicitHeight
      visible: !!root.goal
      Txt {
        id: stageLine
        width: parent.width - paceKey.implicitWidth - Style.space(12)
        text: {
          var g = root.goal, s = root.service
          if (!g) return ""
          if (g.reached) return s.t("goal.reached")
          return s.t("goal.stage").arg(s.money(g.stage.remaining)).arg(s.money(g.stage.target))
        }
      }
      Row {
        id: paceKey
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        visible: !!root.goal && !root.goal.reached
        Rectangle { width: Style.space(2); height: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.prevTick }
        Hint { text: root.goal ? root.service.t("goal.pace").arg(root.service.money(root.goal.paceAmount)) : "" }
      }
    }
    // A key instead of labels on the ticks, so close values can never collide.
    Item {
      width: parent.width; height: Math.max(prevKey.implicitHeight, recordKey.implicitHeight)
      visible: root.racing && !root.goal
      Row {
        id: prevKey
        spacing: Style.space(6)
        visible: !!root.game && root.game.prevSame > 0
        Rectangle { width: Style.space(2); height: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.prevTick }
        Hint { text: root.game ? root.service.t("growth.same-day").arg(root.service.monthShort(root.game.prevMonthIndex)) + "  " + root.service.money(root.game.prevSame) : "" }
      }
      Row {
        id: recordKey
        anchors.right: parent.right
        spacing: Style.space(6)
        visible: !!root.game && !!root.game.record
        Rectangle { width: Style.space(2); height: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.recordTick }
        Hint { text: root.game && root.game.record ? root.service.t("growth.record").arg(root.service.monthOf(root.game.record.month)) + "  " + root.service.money(root.game.record.amount) : "" }
      }
    }
    Hint {
      width: parent.width
      visible: !!root.game && root.game.total === 0
      wrapMode: Text.Wrap
      text: root.service ? root.service.t("growth.first-hint") : ""
    }
    Hint {
      width: parent.width
      visible: !!root.game && root.game.goalCurrency !== ""
      wrapMode: Text.Wrap
      text: root.game && root.service ? root.service.t("goal.mismatch").arg(root.game.goalCurrency).arg(root.service.currency) : ""
    }
    Ui.Button {
      visible: !!root.game && !root.goal
      foreground: Commons.Color.popups.text
      bordered: true
      text: root.service ? root.service.t("goal.set") : ""
      onClicked: root.commandRequested(root.goalWord())
    }
  }

  // Profit sits beside the goal so revenue can't be chased at a loss.
  Row {
    id: goalStats
    width: parent.width
    visible: !!root.goal
    spacing: Style.space(12)
    readonly property real cell: (width - spacing * 2) / 3
    Stat {
      width: goalStats.cell
      label: root.service ? root.service.t("stat.profit") : ""
      value: root.game ? root.service.signed(root.game.profit) : "—"
    }
    Stat {
      width: goalStats.cell
      label: root.game ? root.service.t("growth.same-day").arg(root.service.monthShort(root.game.prevMonthIndex)) : ""
      value: !root.game || root.game.delta === null ? "—" : (root.game.delta >= 0 ? "▲ " : "▼ ") + root.service.number(Math.abs(root.game.delta), 0) + "%"
    }
    Stat {
      width: goalStats.cell
      label: {
        var g = root.game
        if (!g) return ""
        if (g.isRecord) return "★ " + root.service.t("growth.record-badge")
        return g.record ? root.service.t("growth.record").arg(root.service.monthOf(g.record.month)) : root.service.t("stat.record")
      }
      value: !root.game ? "—" : root.game.isRecord ? root.service.money(root.game.current) : root.game.record ? root.service.money(root.game.record.amount) : "—"
    }
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text }

  WeekAction {
    width: parent.width
    service: root.service
    onCommandRequested: function(text) { root.commandRequested(text) }
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text }

  Column {
    width: parent.width
    spacing: Style.space(6)
    Item {
      width: parent.width; height: milestones.implicitHeight
      Ui.PanelSectionHeader { id: milestones; foreground: Commons.Color.popups.text; text: root.service ? root.service.t("growth.milestones") : "" }
      Hint {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        text: root.game ? root.service.t("growth.lifetime").arg(root.service.money(root.game.total)) : ""
      }
    }
    MilestoneLadder {
      id: ladder
      width: parent.width
      steps: root.game ? root.game.ladder : []
      segment: root.game && root.game.next ? root.game.next.segment : 0
    }
    Item {
      width: parent.width; height: nextLine.implicitHeight
      Txt {
        id: nextLine
        width: parent.width - toGo.implicitWidth - Style.space(12)
        text: {
          var g = root.game, s = root.service
          if (!g) return ""
          if (root.hoveredStep) return root.stepText(root.hoveredStep)
          if (!g.next) return s.t("growth.all-done")
          return g.next.target === 1 ? s.t("growth.next-first") : s.t("growth.next").arg(s.money(g.next.target))
        }
      }
      Hint {
        id: toGo
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        visible: !!root.game && !!root.game.next && root.game.next.target > 1 && !root.hoveredStep
        text: root.game && root.game.next ? root.service.t("growth.to-go").arg(root.service.money(root.game.next.remaining)) : ""
      }
    }
    Flow {
      width: parent.width
      spacing: Style.space(6)
      visible: root.extras.length > 0
      Repeater {
        model: root.extras
        Rectangle {
          required property var modelData
          width: pill.implicitWidth + Style.space(14)
          height: pill.implicitHeight + Style.space(6)
          radius: height / 2
          color: Util.alpha(Commons.Color.popups.text, 0.08)
          Hint { id: pill; anchors.centerIn: parent; text: "✓ " + root.service.winTitle(parent.modelData) }
        }
      }
    }
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text }

  Item {
    width: parent.width; height: runwayValue.implicitHeight
    Ui.PanelSectionHeader {
      anchors.verticalCenter: parent.verticalCenter
      foreground: Commons.Color.popups.text
      text: root.service ? root.service.t("growth.runway") : ""
    }
    Txt {
      id: runwayValue
      anchors.right: parent.right
      font.bold: true
      color: root.service && root.service.runway !== null && root.service.runway < 3 ? Commons.Color.urgent : Commons.Color.popups.text
      text: root.service ? root.service.runwayText() : ""
    }
  }
}
