pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An inline question with its two answers, on a line: the question's
// words (wrapping), a Keep button (the default: nothing happens unless the
// confirm one is clicked) and the confirm one. The caller translates the
// texts and hides it (`visible`) once answered. For a click that needs a
// second press instead, see ConfirmGate.
RowLayout {
  id: root

  property string question
  property string keepText: I18n.tr("Keep")
  property string confirmText

  // Keep: leave things as they are
  signal kept
  // The confirm button
  signal confirmed

  spacing: Widget.spacing

  StyledText {
    text: root.question
    overflow: "wrap"
    Layout.fillWidth: true
  }

  StyledTextButton {
    text: root.keepText
    onClicked: root.kept()
  }

  StyledTextButton {
    text: root.confirmText
    onClicked: root.confirmed()
  }
}
