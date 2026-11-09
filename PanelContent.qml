pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "Model.js" as Model

// Separate from Panel.qml so it can be rendered and tested without a bar.
Column {
  id: root
  property var service: null
  property string view: "growth"
  property string scope: "all"
  property bool skipSetup: false
  property string error: ""
  readonly property bool showSetup: !!service && service.needsSetup && !skipSetup
  readonly property Item focusItem: showSetup ? setup.keyField : input
  readonly property bool editing: input.activeFocus || setup.keyField.activeFocus
  readonly property var payload: service ? service.payload : null
  readonly property var command: service ? Model.parseCommand(input.text) : null
  readonly property var parsed: service && !command && input.text.trim() !== "" ? Model.parseEntry(input.text, new Date(), service.businessTag) : null
  readonly property var targetAccount: parsed && parsed.ok && service ? service.previewAccount(parsed.account) : null
  readonly property bool accountMissing: !!parsed && parsed.ok && !targetAccount && !service.isDemo
  readonly property var banners: {
    if (!service || !payload) return []
    var out = []
    if (service.message) out.push({text: service.message, urgent: true})
    if (payload.status === "demo" && !(service.message && payload.reason === "demo.reason.unreachable")) out.push({text: service.t("banner.demo").arg(service.t(payload.reason)), connect: service.needsSetup})
    ;(payload.warnings || []).forEach(function(w) { out.push({text: service.t(w.key).arg(w.arg)}) })
    return out
  }
  signal closeRequested()
  spacing: Style.space(12)

  function reset() { error = ""; skipSetup = false }
  function switchView() { view = view === "growth" ? "money" : "growth" }
  function submit() {
    if (!service || service.saving) return
    error = ""
    if (command) {
      if (!command.ok) { error = service.t("entry." + command.error); return }
      service.runCommand(command)
      input.text = ""
      return
    }
    service.addEntry(input.text, function(ok, text) {
      if (ok) { input.text = ""; root.closeRequested() }
      else root.error = text
    })
  }
  function prefill(text) {
    error = ""
    view = "growth"
    input.text = text
    input.cursorPosition = text.length
    input.forceActiveFocus()
  }
  function commandPreview(c) {
    var s = service
    if (!c.ok) return s.t("entry." + c.error)
    if (c.kind === "goal") return c.off ? s.t("command.goal-off") : s.t("command.goal").arg(s.plainMoney(c.amount)).arg(s.game ? s.monthName(s.game.monthIndex) : "")
    return c.off ? s.t("command.action-off") : s.t("command.action").arg(c.target).arg(c.text)
  }
  function preview() {
    if (!service) return ""
    if (error) return error
    if (command) return commandPreview(command)
    var p = parsed
    if (!p) return service.t("input.hint")
    if (!p.ok) return service.t("entry." + p.error).replace("%1", p.amount || "")
    if (accountMissing) return service.t("input.account-missing").arg(p.account)
    var code = targetAccount ? targetAccount.currency : service.currency
    var parts = [(p.nature === "income" ? "+" : "−") + service.plainMoney(p.amount, code), p.name]
    parts = parts.concat(p.tags.map(function(tag) { return "#" + tag }))
    if (targetAccount) parts.push(targetAccount.name)
    parts.push(service.t(p.offset === 2 ? "date.two-days" : p.offset === 1 ? "date.yesterday" : "date.today"))
    return parts.join("  ·  ")
  }

  SetupView {
    id: setup
    width: parent.width
    visible: root.showSetup
    service: root.service
    onDemoRequested: root.skipSetup = true
  }

  Column {
    width: parent.width
    spacing: Style.space(14)
    visible: !root.showSetup

    Column {
      width: parent.width
      spacing: Style.space(5)
      Ui.TextField {
        id: input
        width: parent.width
        foreground: Commons.Color.popups.text
        placeholderText: root.service ? root.service.t("input.placeholder") : ""
        enabled: !root.service || !root.service.saving
        onAccepted: root.submit()
        onTextEdited: root.error = ""
        Keys.onEscapePressed: root.closeRequested()
        Keys.onTabPressed: root.switchView()
        Keys.onBacktabPressed: root.switchView()
        Keys.onUpPressed: if (input.text === "") root.service.bumpAction(1)
        Keys.onDownPressed: if (input.text === "") root.service.bumpAction(-1)
      }
      Hint {
        width: parent.width
        leftPadding: Style.spacing.controlPaddingX
        color: root.error || root.accountMissing ? Commons.Color.urgent : (root.parsed && root.parsed.ok) || (root.command && root.command.ok) ? Commons.Color.popups.text : Util.alpha(Commons.Color.popups.text, 0.65)
        text: root.preview()
      }
    }

    Repeater {
      model: root.banners
      Rectangle {
        id: banner
        required property var modelData
        width: parent.width
        height: bannerRow.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: Util.alpha(banner.modelData.urgent ? Commons.Color.urgent : Commons.Color.popups.text, 0.1)
        Item {
          id: bannerRow
          anchors.centerIn: parent
          width: parent.width - Style.space(20)
          implicitHeight: Math.max(bannerText.implicitHeight, bannerAction.visible ? bannerAction.implicitHeight : 0)
          Hint {
            id: bannerText
            anchors.left: parent.left
            anchors.right: bannerAction.visible ? bannerAction.left : parent.right
            anchors.rightMargin: bannerAction.visible ? Style.space(8) : 0
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.Wrap
            color: banner.modelData.urgent ? Commons.Color.urgent : Commons.Color.popups.text
            text: banner.modelData.text
          }
          Ui.Button {
            id: bannerAction
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            visible: banner.modelData.connect === true
            foreground: Commons.Color.popups.text
            bordered: true
            text: root.service ? root.service.t("banner.connect") : ""
            onClicked: root.skipSetup = false
          }
        }
      }
    }

    Item {
      width: parent.width
      height: viewSwitch.implicitHeight
      Ui.ButtonGroup {
        id: viewSwitch
        focusable: false
        foreground: Commons.Color.popups.text
        value: root.view
        options: root.service ? [{value: "growth", label: root.service.t("view.growth")}, {value: "money", label: root.service.t("view.money")}] : []
        onChanged: function(value) { root.view = value; input.forceActiveFocus() }
      }
      Ui.ButtonGroup {
        anchors.right: parent.right
        visible: root.view === "money" && !!root.service && !root.service.trackAllIncome
        focusable: false
        foreground: Commons.Color.popups.text
        value: root.scope
        options: root.service ? [{value: "all", label: root.service.t("scope.all")}, {value: "business", label: root.service.t("scope.business")}] : []
        onChanged: function(value) { root.scope = value; input.forceActiveFocus() }
      }
    }

    GrowthView { width: parent.width; visible: root.view === "growth"; service: root.service; onCommandRequested: function(text) { root.prefill(text) } }
    MoneyView { width: parent.width; visible: root.view === "money"; service: root.service; scope: root.scope }

    Ui.PanelSeparator { foreground: Commons.Color.popups.text }

    Item {
      width: parent.width
      height: actions.implicitHeight
      Hint {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.service ? root.service.updatedText() : ""
      }
      Row {
        id: actions
        anchors.right: parent.right
        spacing: Style.space(4)
        Ui.PanelActionButton {
          visible: !!root.service && !!root.service.lastAdded
          iconText: "󰕌"; foreground: Commons.Color.popups.text
          tooltipText: root.service ? root.service.t("action.undo") : ""
          onClicked: root.service.undoLast()
        }
        Ui.PanelActionButton {
          iconText: root.service && root.service.amountsHidden ? "󰈉" : "󰈈"; foreground: Commons.Color.popups.text
          tooltipText: !root.service ? "" : root.service.t(root.service.amountsHidden ? "action.show" : "action.hide")
          onClicked: root.service.toggleAmounts()
        }
        Ui.PanelActionButton {
          iconText: "󰑐"; foreground: Commons.Color.popups.text
          enabled: !!root.service && !root.service.busy
          tooltipText: root.service ? root.service.t("action.refresh") : ""
          onClicked: root.service.refresh()
        }
        Ui.PanelActionButton {
          iconText: "󰈠"; foreground: Commons.Color.popups.text
          tooltipText: root.service ? root.service.t("action.import") : ""
          onClicked: { root.closeRequested(); root.service.openImport() }
        }
        Ui.PanelActionButton {
          iconText: "󰏌"; foreground: Commons.Color.popups.text
          tooltipText: root.service ? root.service.t("action.open") : ""
          onClicked: { root.closeRequested(); root.service.openSure() }
        }
      }
    }
  }
}
