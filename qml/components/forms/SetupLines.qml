pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Lines for the user's config: where they go (`hint`), the text (`lines`),
// Copy, and Add it for me (with a backup) while `canAdd`. The caller does
// the copying and the adding (copyClicked, addClicked).
ColumnLayout {
  id: block

  property string hint
  property string lines
  property bool canAdd
  property bool adding
  property bool added

  signal copyClicked
  signal addClicked

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledText {
    text: block.hint
    role: "caption"
    Layout.fillWidth: true
  }

  Surface {
    tone: "sunken"
    outlined: true
    Layout.fillWidth: true
    implicitHeight: linesText.implicitHeight + Widget.padding * 2

    StyledText {
      id: linesText
      anchors.fill: parent
      anchors.margins: Widget.padding
      text: block.lines
      role: "body"
      textFamily: "monospace"
      overflow: "wrap"
    }
  }

  RowLayout {
    spacing: Widget.spacing

    StyledTextButton {
      text: I18n.tr("Copy")
      onClicked: block.copyClicked()
    }

    StyledTextButton {
      visible: block.canAdd
      enabled: !block.adding && !block.added
      text: block.added ? I18n.tr("Added") : block.adding ? I18n.tr("Adding…") : I18n.tr("Add it for me")
      onClicked: block.addClicked()
    }
  }
}
