import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui

// Last month against its goal. Shown until dismissed, with no penalty carried forward.
Rectangle {
  id: root
  property var service: null
  readonly property var review: service && service.game ? service.game.review : null
  signal changeRequested()
  implicitHeight: body.implicitHeight + Style.space(20)
  radius: Style.cornerRadius
  color: Util.alpha(Commons.Color.popups.text, 0.08)

  function details() {
    var r = review, s = service, out = []
    if (r.best) out.push(s.t("review.best"))
    out.push(s.t("review.profit").arg(s.signed(r.profit)))
    if (r.weeks.total > 0) out.push(s.t("review.weeks").arg(r.weeks.done).arg(r.weeks.total))
    return out.join("  ·  ")
  }

  Column {
    id: body
    x: Style.space(10); y: Style.space(10)
    width: parent.width - Style.space(20)
    spacing: Style.space(4)
    Ui.PanelSectionHeader {
      foreground: Commons.Color.popups.text
      text: root.review ? root.service.t("review.title").arg(root.service.monthName(root.review.monthIndex)) : ""
    }
    Txt {
      width: parent.width
      font.bold: true
      font.pixelSize: Style.font.title
      text: root.review ? root.service.t("review.line").arg(root.service.money(root.review.income)).arg(root.service.money(root.review.target)).arg(root.review.percent) : ""
    }
    Hint {
      width: parent.width
      color: root.review && root.review.reached ? Commons.Color.accent : Util.alpha(Commons.Color.popups.text, 0.65)
      text: root.review ? root.service.t(root.review.reached ? "review.reached" : "review.fresh") : ""
    }
    Hint { width: parent.width; wrapMode: Text.Wrap; text: root.review ? root.details() : "" }
    Row {
      spacing: Style.space(8)
      topPadding: Style.space(4)
      Ui.Button {
        foreground: Commons.Color.popups.text
        bordered: true
        text: root.service ? root.service.t("review.keep") : ""
        onClicked: root.service.dismissReview()
      }
      Ui.Button {
        foreground: Commons.Color.popups.text
        bordered: true
        text: root.service ? root.service.t("review.change") : ""
        onClicked: { root.changeRequested(); root.service.dismissReview() }
      }
    }
  }
}
