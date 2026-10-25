pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components.reusable
import qs.config
import qs.services.ui

// Save and Discard (both shown while `dirty`, or while a box in this window
// holds typed text: EditsManager.typingField) for whichever service owns a
// page's pending edits. Save commits that text first, Discard drops it;
// `reset` drops the edits back to what's saved. `compact` drops the labels
// to icons with tooltips, for headers too narrow for both.
RowLayout {
  id: root

  property bool dirty: false
  // Save stays visible while dirty but is disabled when false
  property bool canSave: true
  property string saveLabel: I18n.tr("Save")
  property bool compact: false
  // Width with labels, whatever `compact` is (for callers deciding it)
  readonly property real fullWidth: saveButton.fullWidth + resetButton.fullWidth + root.spacing

  signal save
  signal reset

  readonly property bool _typing: EditsManager.typingField !== null && EditsManager.typingWindow === root.Window.window

  spacing: Widget.spacing

  ActionButton {
    id: saveButton
    visible: root.dirty || root._typing
    enabled: root.canSave
    icon: "check"
    label: root.saveLabel
    fillColor: hovered ? Qt.lighter(Theme.accent, 1.1) : Theme.accent
    contentColor: Theme.background
    onClicked: {
      EditsManager.commitTyping();
      root.save();
    }
  }

  ActionButton {
    id: resetButton
    visible: root.dirty || root._typing
    icon: "undo"
    label: I18n.tr("Discard")
    fillColor: Theme.backgroundHighlight
    strokeColor: hovered ? Theme.accent : Theme.border
    contentColor: Theme.foreground
    onClicked: {
      EditsManager.discardTyping();
      root.reset();
    }
  }

  // Sized to its label (translations differ in width, and fonts in height),
  // at least `minWidth` so Save and Discard line up in English
  component ActionButton: Rectangle {
    id: button

    property string icon
    property string label
    property color fillColor
    property color strokeColor: "transparent"
    property color contentColor
    readonly property bool hovered: area.containsMouse
    readonly property int minWidth: Widget.px(80)
    readonly property real fullWidth: Math.max(button.minWidth, buttonIcon.implicitWidth + buttonText.implicitWidth + buttonRow.spacing + Widget.padding * 2)

    signal clicked

    Layout.preferredWidth: root.compact ? Layout.preferredHeight : button.fullWidth
    Layout.preferredHeight: Math.max(Widget.height - Widget.px(4), buttonRow.implicitHeight + Widget.spacing * 2)
    color: button.fillColor
    radius: Widget.radius
    border.color: button.strokeColor
    border.width: 1
    opacity: button.enabled ? 1 : 0.4

    RowLayout {
      id: buttonRow
      anchors.centerIn: parent
      spacing: Widget.spacing

      StyledIcon {
        id: buttonIcon
        text: button.icon
        textSize: Appearance.fontSize
        textColor: button.contentColor
        Layout.alignment: Qt.AlignVCenter
      }

      StyledText {
        id: buttonText
        visible: !root.compact
        text: button.label
        textSize: Appearance.fontSizeBy(-1)
        textColor: button.contentColor
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }

    LazyLoader {
      active: root.compact && button.hovered
      StyledToolTip {
        target: button
        text: button.label
      }
    }
  }
}
