import QtQuick
import qs.Commons
import qs.Commons as Commons

// Every label in the plugin: data from Sure is untrusted, so never rich text.
Text {
  textFormat: Text.PlainText
  color: Commons.Color.popups.text
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
}
