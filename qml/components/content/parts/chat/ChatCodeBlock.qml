pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.methods

// A fenced code block in a reply: its language, a copy button and the code
// in a monospace font. `open` while its closing fence is still streaming in.
Surface {
  id: root
  tone: "sunken"

  property string code: ""
  property string lang: ""
  property bool open: false

  property bool _copied: false

  implicitHeight: column.implicitHeight
  clip: true

  ColumnLayout {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 0

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Widget.padding
      Layout.rightMargin: Widget.spacing
      Layout.topMargin: Widget.spacing / 2
      Layout.bottomMargin: Widget.spacing / 2
      spacing: Widget.spacing / 2

      StyledLabel {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.lang || I18n.tr("code")
        role: "micro"
        textFamily: "monospace"
      }

      FlatIconButton {
        size: Widget.iconButton
        iconText: root._copied ? "check" : "content_copy"
        iconSize: Style.iconSm
        iconColor: root._copied ? Style.success : Style.textMuted
        tooltipText: I18n.tr("Copy")
        onClicked: {
          ClipboardManager.copyText(root.code);
          root._copied = true;
          copiedTimer.restart();
        }
      }
    }

    StyledSeparator {
      backTone: "sunken"
      Layout.fillWidth: true
    }

    TextEdit {
      id: codeText
      renderType: TextRender.typeFor(TextRender.zoomAt(parent), false, 0)
      Layout.fillWidth: true
      Layout.margins: Widget.padding
      text: root.code
      readOnly: true
      selectByMouse: true
      wrapMode: TextEdit.WrapAnywhere
      textFormat: TextEdit.PlainText
      color: Style.text
      selectionColor: Style.accent
      selectedTextColor: Style.inkAccent.text
      font.family: "monospace"
      font.pixelSize: Style.typeCaption

      HoverHandler {
        cursorShape: Qt.IBeamCursor
      }
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root._copied = false
  }
}
