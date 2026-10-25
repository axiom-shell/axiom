pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// Buttons that add a bar button (one per bar) or a keybind opening what
// the layouts editor has selected. Other editors save those, so the
// buttons are off, with `unsavedHint` above them, until it's `saved`
ColumnLayout {
  id: root

  required property bool saved
  required property string unsavedHint
  readonly property var bars: BarManager.localConfig ?? Bar.savedBars

  signal barButtonRequested(int barIndex)
  signal keybindRequested

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledText {
    visible: !root.saved
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: root.unsavedHint
    textSize: Appearance.fontSizeBy(-2)
    opacity: 0.7
  }

  Flow {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2
    enabled: root.saved
    opacity: enabled ? 1 : 0.5

    Repeater {
      model: root.bars.length

      StyledTextButton {
        required property int index
        iconText: "add"
        text: I18n.tr("Button on {0}", BarManager.barLabel(index))
        textPadding: Widget.smallPadding
        onClicked: root.barButtonRequested(index)
      }
    }

    StyledTextButton {
      iconText: "keyboard"
      text: I18n.tr("Add a keybind")
      textPadding: Widget.smallPadding
      onClicked: root.keybindRequested()
    }
  }
}
