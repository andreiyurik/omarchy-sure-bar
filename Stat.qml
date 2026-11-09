import QtQuick
import qs.Commons
import qs.Commons as Commons

Column {
  id: root
  property string label: ""
  property string value: ""
  property color valueColor: Commons.Color.popups.text
  spacing: Style.space(2)
  Hint { width: parent.width; text: root.label }
  Txt { width: parent.width; text: root.value; color: root.valueColor; font.bold: true; font.pixelSize: Style.font.title }
}
