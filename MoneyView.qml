pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

Column {
  id: root
  property var service: null
  property string scope: "all"
  readonly property bool scoped: !!service && !service.trackAllIncome
  readonly property bool business: scope === "business" && scoped
  readonly property var payload: service ? service.payload : null
  readonly property var current: Model.view(payload, business ? "business" : "all")
  readonly property var budget: payload ? payload.budget : null
  readonly property var game: service ? service.game : null
  readonly property var recent: !payload ? [] : business ? payload.business.recent || [] : payload.recent
  spacing: Style.space(14)

  Column {
    width: parent.width
    spacing: Style.space(4)
    Ui.PanelSectionHeader {
      foreground: Commons.Color.popups.text
      text: root.game ? root.service.t("money.net").arg(root.service.monthName(root.game.monthIndex)) : ""
    }
    Txt {
      width: parent.width
      font.pixelSize: Style.font.displayLarge
      font.bold: true
      text: root.service ? root.service.signed(root.current.month.net) : ""
    }
    Hint {
      width: parent.width
      text: root.service ? root.service.t("money.flow").arg(root.service.money(root.current.month.income)).arg(root.service.money(root.current.month.spending)) : ""
    }
  }

  Row {
    id: stats
    width: parent.width
    spacing: Style.space(12)
    readonly property real cell: (width - spacing * 2) / 3
    readonly property string rate: root.current.month.rate === null || !root.service ? "—" : root.service.number(Math.round(root.current.month.rate), 0) + "%"
    Stat {
      width: stats.cell
      label: root.service ? root.service.t(root.business ? "stat.margin" : "stat.savings") : ""
      value: stats.rate
    }
    Stat {
      width: stats.cell
      label: root.service ? root.service.t(root.business ? "stat.burn" : "stat.net-worth") : ""
      value: !root.service || !root.payload ? "—" : root.business ? root.service.money(root.current.burn) : root.service.money(root.payload.netWorth)
    }
    Stat {
      width: stats.cell
      label: root.service ? root.service.t(root.business ? "stat.income" : "stat.runway") : ""
      value: !root.service ? "—" : root.business ? root.service.money(root.current.month.income) : root.service.runwayText()
      valueColor: !root.business && root.service && root.service.runway !== null && root.service.runway < 3 ? Commons.Color.urgent : Commons.Color.popups.text
    }
  }

  CashflowChart { width: parent.width; service: root.service; series: root.current.series }

  Hint {
    width: parent.width
    wrapMode: Text.Wrap
    visible: root.business && root.current.skipped > 0
    text: root.service ? root.service.tn("warn.skipped", root.current.skipped).arg(root.current.skipped) : ""
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text; visible: budgetBlock.visible }

  Column {
    id: budgetBlock
    width: parent.width
    spacing: Style.space(6)
    visible: !root.business && !!root.payload && root.payload.categories.length > 0
    readonly property real elapsed: root.budget && root.budget.pace ? root.budget.pace.elapsed / 100 : -1
    Item {
      width: parent.width; height: budgetHead.implicitHeight
      Ui.PanelSectionHeader { id: budgetHead; foreground: Commons.Color.popups.text; text: root.service ? root.service.t("budget.title") : "" }
      Hint {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        visible: !!root.budget && !!root.budget.pace
        text: root.budget && root.budget.pace ? root.service.t("budget.pace").arg(root.budget.pace.percent).arg(root.budget.pace.elapsed) : ""
      }
    }
    Repeater {
      model: root.payload ? root.payload.categories.slice(0, 5) : []
      Column {
        id: line
        required property var modelData
        width: parent.width
        spacing: 0
        readonly property real ratio: modelData.total > 0 ? modelData.spent / modelData.total : 0
        Item {
          width: parent.width; height: name.implicitHeight
          Txt { id: name; width: parent.width * 0.5; text: line.modelData.name }
          Hint { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.service.money(line.modelData.spent) + " / " + root.service.money(line.modelData.total) }
        }
        Meter {
          width: parent.width
          ratio: line.ratio
          fill: line.ratio >= 1 ? Commons.Color.urgent : Util.alpha(Commons.Color.popups.text, 0.7)
          ticks: budgetBlock.elapsed >= 0 ? [{ratio: budgetBlock.elapsed, color: Util.alpha(Commons.Color.popups.text, 0.45)}] : []
        }
      }
    }
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text; visible: recentBlock.visible }

  Column {
    id: recentBlock
    width: parent.width
    spacing: Style.space(5)
    visible: root.recent.length > 0
    Ui.PanelSectionHeader { foreground: Commons.Color.popups.text; text: root.service ? root.service.t("recent.title") : "" }
    Repeater {
      model: root.recent.slice(0, 4)
      Item {
        id: row
        required property var modelData
        width: parent.width; height: title.implicitHeight
        Txt { id: title; width: Math.min(implicitWidth, parent.width * 0.55); text: row.modelData.name }
        Hint {
          anchors.left: title.right; anchors.leftMargin: Style.space(8)
          anchors.right: sum.left; anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.category
        }
        Txt { id: sum; anchors.right: parent.right; text: root.service.signed(row.modelData.amount, row.modelData.currency) }
      }
    }
  }
}
