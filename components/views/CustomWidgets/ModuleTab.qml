pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Custom widgets page, Module tab: the module's design (its canvas comes
// with the editor's second part)
ColumnLayout {
  id: root

  required property var grid

  width: parent?.width ?? 0

  StyledText {
    text: I18n.tr("The module editor isn't here yet.")
  }
}
