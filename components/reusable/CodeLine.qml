pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system

// Text to paste somewhere (a config line, a command), in a monospace box
// with a Copy button
Rectangle {
  id: root

  property string text

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight + Widget.padding
  radius: Widget.radius
  color: Theme.backgroundAlt
  border.color: Theme.border
  border.width: Appearance.borderWidth

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: Widget.padding / 2
    anchors.leftMargin: Widget.padding
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: root.text
      textFamily: "monospace"
      wrapMode: Text.WrapAnywhere
    }

    StyledTextButton {
      id: copyButton
      property bool copied: false
      Layout.alignment: Qt.AlignTop
      text: copied ? I18n.tr("Copied") : I18n.tr("Copy")
      iconText: copied ? "check" : "content_copy"
      onClicked: {
        ClipboardManager.copyText(root.text);
        copied = true;
        copiedTimer.restart();
      }

      Timer {
        id: copiedTimer
        interval: 2000
        onTriggered: copyButton.copied = false
      }
    }
  }
}
