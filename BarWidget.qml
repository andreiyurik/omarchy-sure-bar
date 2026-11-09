import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "andreiyurik.sure-bar"
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var payload: service ? service.payload : null
  readonly property bool opened: popup.opened
  readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Binding {
    target: root.service
    property: "widgetSettings"
    value: root.settings || ({})
    when: !!root.service
  }

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.toggle() }
  function closeForPopoutSwitch() { popup.closeForPopoutSwitch() }

  function tooltip() {
    var s = service
    if (!s) return "Sure"
    if (s.needsSetup) return s.t("tooltip.setup")
    if (s.message) return s.message
    if (s.isDemo) return s.t("tooltip.demo")
    var lines = [s.t("tooltip.revenue").arg(s.money(s.game.current)), s.raceText(s.game)]
    var pace = payload.budget ? payload.budget.pace : null
    lines.push(pace ? s.t("tooltip.budget").arg(pace.percent).arg(pace.elapsed) : s.t("tooltip.no-budget"))
    if (s.runway !== null && s.runway < 3) lines.push(s.t("tooltip.runway-low"))
    return lines.join("\n")
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service ? root.service.barText(root.vertical) : "◎"
    foreground: root.service && root.service.alarm ? Commons.Color.urgent : (root.bar ? root.bar.barForeground : Commons.Color.foreground)
    dimmed: !root.service || root.service.isDemo || root.service.message !== ""
    tooltipText: root.tooltip()
    onPressed: function(code) {
      if (code === Qt.MiddleButton) { if (root.service) root.service.refresh(true) }
      else root.toggle()
    }
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
  }

  Panel {
    id: popup
    bar: root.bar
    moduleName: root.moduleName
    settings: root.settings
    anchorItem: button
    hostWidget: root
    service: root.service
  }
}
