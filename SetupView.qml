pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

Column {
  id: root
  property var service: null
  readonly property alias firstField: urlField
  readonly property bool editing: urlField.activeFocus || keyField.activeFocus
  readonly property bool hasWorkingData: !!service && service.hasKey && !service.needsSetup
  readonly property string problem: {
    if (!service) return ""
    if (service.setupError) return service.t(service.setupError).replace("%1", service.errorArg)
    if (service.setupReason.indexOf("url-") === 0) return service.t("setup." + service.setupReason)
    return service.setupReason === "rejected" ? service.t("setup.rejected") : ""
  }
  signal demoRequested()
  signal backRequested()
  spacing: Style.space(14)

  function submit() { if (service) service.connect(urlField.text, keyField.text) }

  component Step: Row {
    id: step
    property string number: ""
    property string label: ""
    width: parent.width
    spacing: Style.space(8)
    Rectangle {
      width: Style.space(20); height: width; radius: width / 2
      color: Util.alpha(Commons.Color.popups.text, 0.1)
      Hint { anchors.centerIn: parent; text: step.number; color: Commons.Color.popups.text }
    }
    Txt {
      width: parent.width - Style.space(28)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.Wrap
      text: step.label
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(4)
    Txt { width: parent.width; font.pixelSize: Style.font.display; font.bold: true; text: root.service ? root.service.t("setup.title") : "" }
    Hint { width: parent.width; wrapMode: Text.Wrap; text: root.service ? root.service.t("setup.intro") : "" }
  }

  Txt { width: parent.width; visible: root.problem !== ""; wrapMode: Text.Wrap; color: Commons.Color.urgent; text: root.problem }

  Column {
    width: parent.width
    spacing: Style.space(8)
    Step { number: "1"; label: root.service ? root.service.t("setup.step-server") : "" }
    Ui.TextField {
      id: urlField
      anchors.left: parent.left; anchors.leftMargin: Style.space(28)
      width: parent.width - Style.space(28)
      foreground: Commons.Color.popups.text
      placeholderText: root.service ? root.service.t("setup.url-placeholder") : ""
      text: root.service ? root.service.rawUrl : ""
      inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
      enabled: !root.service || !root.service.connecting
      onAccepted: keyField.forceActiveFocus()
      Keys.onEscapePressed: root.backRequested()
    }
    Step { number: "2"; label: root.service ? root.service.t("setup.step-key") : "" }
    Ui.Button {
      anchors.left: parent.left; anchors.leftMargin: Style.space(28)
      foreground: Commons.Color.popups.text
      bordered: true
      text: root.service ? root.service.t("setup.open-keys") : ""
      onClicked: root.service.openApiKeys(urlField.text)
    }
    Step { number: "3"; label: root.service ? root.service.t("setup.step-paste") : "" }
    Ui.TextField {
      id: keyField
      anchors.left: parent.left; anchors.leftMargin: Style.space(28)
      width: parent.width - Style.space(28)
      password: true
      foreground: Commons.Color.popups.text
      placeholderText: !root.service ? "" : root.service.t(root.service.hasKey ? "setup.placeholder-keep" : "setup.placeholder")
      enabled: !root.service || !root.service.connecting
      onAccepted: root.submit()
      Keys.onEscapePressed: root.backRequested()
    }
    Row {
      anchors.left: parent.left; anchors.leftMargin: Style.space(28)
      spacing: Style.space(8)
      Ui.Button {
        foreground: Commons.Color.popups.text
        bordered: true
        selected: true
        text: !root.service ? "" : root.service.connecting ? root.service.t("setup.connecting") : root.service.t("setup.connect")
        onClicked: root.submit()
      }
      Ui.Button {
        visible: root.hasWorkingData
        foreground: Commons.Color.popups.text
        bordered: true
        text: root.service ? root.service.t("setup.back") : ""
        onClicked: root.backRequested()
      }
    }
  }

  Ui.PanelSeparator { foreground: Commons.Color.popups.text }

  Column {
    width: parent.width
    spacing: Style.space(3)
    Hint { width: parent.width; wrapMode: Text.Wrap; visible: root.hasWorkingData; text: !root.service ? "" : root.service.t(root.service.readOnly ? "setup.access-read" : "setup.access-write") }
    Hint { width: parent.width; wrapMode: Text.Wrap; text: root.service ? root.service.t("setup.storage") : "" }
  }

  Ui.Button {
    visible: !root.hasWorkingData
    foreground: Commons.Color.popups.text
    text: root.service ? root.service.t("setup.demo") : ""
    onClicked: root.demoRequested()
  }
}
