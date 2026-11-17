pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// Text to paste somewhere (a config line, a command), in a monospace box
// with a Copy button (`copyable` off drops it: a script shown to read). A
// `title` is a faint caption above the text (a path); `multiLine` shows the
// text's own line breaks (a script), else they read as spaces.
Surface {
  id: root
  tone: "sunken"
  outlined: false

  property string text
  property bool copyable: true
  // A faint line above the text; none while empty
  property string title: ""
  // The text's own line breaks show (a script); else it is one wrapping
  // run and the breaks read as spaces
  property bool multiLine: false

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight + Widget.padding

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Widget.padding / 2
    anchors.leftMargin: Widget.padding
    spacing: Widget.spacing / 2

    StyledText {
      Layout.fillWidth: true
      visible: root.title !== ""
      text: root.title
      role: "caption"
      tone: "faint"
      overflow: "line"
      elide: Text.ElideMiddle // style-exempt: a path, its ends say the most
    }

    RowLayout {
      id: row
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: root.multiLine ? root.text : root.text.replace(/\n/g, " ")
        textFamily: "monospace"
        overflow: "wrap"
      }

      StyledTextButton {
        id: copyButton
        visible: root.copyable
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
}
