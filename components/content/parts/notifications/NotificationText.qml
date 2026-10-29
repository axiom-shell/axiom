pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// A notification's summary and body (from a Notification or a history
// entry). Clickable while the live notification has a default action, or
// with `clickable`; a click emits activated, and the caller runs it
// (NotificationManager.activate). A TapHandler rather than a MouseArea, so
// a swipe handler around it still sees the press. Links in the body open
// in their app.
Item {
  id: root

  required property var notification
  // Whose actions to use: a live Notification, or null
  property var live: notification
  property int summaryLines: 1
  property int bodyLines: 4
  property bool clickable: !!defaultAction

  signal activated

  readonly property var defaultAction: (live?.actions ?? []).find(a => a.identifier === "default")

  Layout.fillWidth: true
  implicitHeight: textColumn.implicitHeight

  HoverHandler {
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
  }

  TapHandler {
    enabled: root.clickable
    onTapped: root.activated()
  }

  ColumnLayout {
    id: textColumn
    width: parent.width
    spacing: 2

    StyledText {
      Layout.fillWidth: true
      text: root.notification?.summary || ""
      font.bold: true
      elide: Text.ElideRight
      maximumLineCount: root.summaryLines
      wrapMode: root.summaryLines > 1 ? Text.Wrap : Text.NoWrap
    }

    StyledText {
      visible: (root.notification?.body ?? "") !== ""
      Layout.fillWidth: true
      text: root.notification?.body ?? ""
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: Text.Wrap
      maximumLineCount: root.bodyLines
      elide: Text.ElideRight
      linkColor: Theme.accent
      onLinkActivated: link => NotificationManager.openLink(link)

      HoverHandler {
        cursorShape: parent.hoveredLink !== "" || root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      }
    }
  }
}
