import QtQuick
import qs.Commons
import qs.Commons as Commons

// Income grows up from zero, spending grows down, the dot is what was left.
// The newest month is drawn fainter because it is not finished yet.
Column {
  id: root
  property var service: null
  property var series: []
  property int hovered: -1
  readonly property color incomeColor: Commons.Color.popups.text
  readonly property color spendingColor: Util.alpha(Commons.Color.popups.text, 0.38)
  readonly property color netColor: Commons.Color.accent
  readonly property color surface: Commons.Color.popups.background
  readonly property color rule: Util.alpha(Commons.Color.popups.text, 0.22)
  readonly property int activeIndex: hovered >= 0 ? hovered : series.length - 1
  readonly property var point: series.length ? series[Math.min(activeIndex, series.length - 1)] : null
  readonly property real maxUp: Math.max.apply(null, [1].concat(series.map(function(m) { return m.income })))
  readonly property real maxDown: Math.max.apply(null, [1].concat(series.map(function(m) { return m.spending })))
  spacing: Style.space(6)

  onSeriesChanged: plot.requestPaint()
  onHoveredChanged: plot.requestPaint()
  onWidthChanged: plot.requestPaint()
  onIncomeColorChanged: plot.requestPaint()
  onNetColorChanged: plot.requestPaint()
  onSurfaceChanged: plot.requestPaint()

  component Key: Column {
    id: key
    property string label: ""
    property string value: ""
    property color swatch: "transparent"
    property bool round: false
    spacing: Style.space(1)
    Row {
      spacing: Style.space(5)
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8); height: width
        radius: key.round ? width / 2 : Style.space(2)
        color: key.swatch
      }
      Hint { text: key.label }
    }
    Txt { width: parent.width; text: key.value; font.bold: true }
  }

  Hint {
    width: parent.width
    text: {
      if (!root.point || !root.service) return root.service ? root.service.t("chart.empty") : ""
      var name = root.service.monthName(parseInt(root.point.month.slice(5, 7), 10) - 1)
      name = name.charAt(0).toUpperCase() + name.slice(1)
      return root.activeIndex === root.series.length - 1 ? root.service.t("chart.so-far").arg(name) : name
    }
  }

  Row {
    width: parent.width
    readonly property real cell: width / 3
    Key {
      width: parent.cell; swatch: root.incomeColor
      label: root.service ? root.service.t("chart.income") : ""
      value: root.point && root.service ? root.service.money(root.point.income) : "—"
    }
    Key {
      width: parent.cell; swatch: root.spendingColor
      label: root.service ? root.service.t("chart.spending") : ""
      value: root.point && root.service ? root.service.money(root.point.spending) : "—"
    }
    Key {
      width: parent.cell; swatch: root.netColor; round: true
      label: root.service ? root.service.t("chart.net") : ""
      value: root.point && root.service ? root.service.signed(root.point.income - root.point.spending) : "—"
    }
  }

  Canvas {
    id: plot
    width: parent.width
    height: Style.space(110)
    Accessible.role: Accessible.Graphic
    Accessible.name: root.point && root.service ? root.service.t("chart.income") + " " + root.service.money(root.point.income) + ", " + root.service.t("chart.spending") + " " + root.service.money(root.point.spending) : ""
    onHeightChanged: requestPaint()

    function bar(ctx, x, y, w, h, up) {
      if (h <= 0) return
      var r = Math.min(Style.space(3), w / 2, h)
      ctx.beginPath()
      if (up) {
        ctx.moveTo(x, y + h); ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r); ctx.lineTo(x + w, y + h)
      } else {
        ctx.moveTo(x, y); ctx.lineTo(x, y + h - r); ctx.quadraticCurveTo(x, y + h, x + r, y + h)
        ctx.lineTo(x + w - r, y + h); ctx.quadraticCurveTo(x + w, y + h, x + w, y + h - r); ctx.lineTo(x + w, y)
      }
      ctx.closePath()
      ctx.fill()
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var count = root.series.length
      if (!count || height <= 0 || width <= 0) return
      var gapY = Style.space(2), usable = height - gapY * 2 - Style.space(4)
      var unit = usable / (root.maxUp + root.maxDown), zero = Style.space(2) + root.maxUp * unit
      var slot = width / count, barWidth = Math.min(slot * 0.3, Style.space(18))
      if (root.hovered >= 0) {
        ctx.fillStyle = Qt.rgba(root.incomeColor.r, root.incomeColor.g, root.incomeColor.b, 0.07)
        ctx.fillRect(slot * root.hovered, 0, slot, height)
      }
      for (var i = 0; i < count; ++i) {
        var m = root.series[i], x = slot * (i + 0.5) - barWidth / 2
        ctx.globalAlpha = i === count - 1 ? 0.55 : 1
        ctx.fillStyle = root.incomeColor
        bar(ctx, x, zero - gapY / 2 - m.income * unit, barWidth, m.income * unit, true)
        ctx.fillStyle = root.spendingColor
        bar(ctx, x, zero + gapY / 2, barWidth, m.spending * unit, false)
      }
      ctx.globalAlpha = 1
      ctx.fillStyle = root.rule
      ctx.fillRect(0, zero - 0.5, width, 1)
      var radius = Style.space(4)
      for (var j = 0; j < count; ++j) {
        var p = root.series[j], cx = slot * (j + 0.5), cy = zero - (p.income - p.spending) * unit
        ctx.fillStyle = root.surface
        ctx.beginPath(); ctx.arc(cx, cy, radius + Style.space(2), 0, Math.PI * 2); ctx.fill()
        ctx.fillStyle = root.netColor
        ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.fill()
      }
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onPositionChanged: function(mouse) { if (root.series.length) root.hovered = Math.max(0, Math.min(root.series.length - 1, Math.floor(mouse.x / (width / root.series.length)))) }
      onExited: root.hovered = -1
    }
  }

  Row {
    width: parent.width
    Repeater {
      model: root.series
      Hint {
        required property var modelData
        required property int index
        width: parent.width / Math.max(1, root.series.length)
        horizontalAlignment: Text.AlignHCenter
        color: index === root.activeIndex ? Commons.Color.popups.text : Util.alpha(Commons.Color.popups.text, 0.65)
        text: root.service ? root.service.monthOf(modelData.month) : ""
      }
    }
  }
}
