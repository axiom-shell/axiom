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
    opacity: 0.7
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledContainer {
    Layout.fillWidth: true
    implicitHeight: linesText.implicitHeight + Widget.padding * 2
    backgroundColor: Theme.background

    StyledText {
      id: linesText
      anchors.fill: parent
      anchors.margins: Widget.padding
      text: block.lines
      textFamily: "monospace"
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WrapAnywhere
    }
  }

  RowLayout {
    spacing: Widget.spacing

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Copy")
      onClicked: block.copyClicked()
    }

    StyledTextButton {
      visible: block.canAdd
      enabled: !block.adding && !block.added
      implicitHeight: Widget.height - Widget.px(4)
      text: block.added ? I18n.tr("Added") : block.adding ? I18n.tr("Adding…") : I18n.tr("Add it for me")
      onClicked: block.addClicked()
    }
  }
}
