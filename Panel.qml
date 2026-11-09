pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui as Ui

Ui.Panel {
  id: root
  manageIpc: false
  property Item anchorItem: null
  property var hostWidget: null
  property var service: null
  onOpenedChanged: if (opened) { content.reset(); if (service) service.refreshIfStale() }

  Ui.KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem; bar: root.bar; owner: root.hostWidget || root
    open: root.opened; focusTarget: content.focusItem
    contentWidth: fittedContentWidth(Style.space(440))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(760))

    Ui.PanelKeyCatcher {
      anchors.fill: parent
      blocked: content.editing
      onCloseRequested: root.close()

      Flickable {
        anchors.fill: parent; clip: true
        contentWidth: width; contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        PanelContent {
          id: content
          width: parent.width
          service: root.service
          onCloseRequested: root.close()
        }
      }
    }
  }
}
