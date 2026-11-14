pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.reusable
import qs.config
import qs.services.ui

// Save and Discard (both shown while `dirty`, Discard only with `canReset`,
// or while a box in this window holds typed text:
// EditsManager.typingField) for whichever service owns a
// page's pending edits. Save commits that text first, Discard drops it;
// `reset` drops the edits back to what's saved. `compact` drops the labels
// to icons with tooltips, for headers too narrow for both. Save is a
// primary StyledTextButton, Discard a text one.
RowLayout {
  id: root

  property bool dirty: false
  // Save stays visible while dirty but is disabled when false
  property bool canSave: true
  // Discard shows while dirty only when true: false when `dirty` can mean
  // something other than unsaved edits (MonitorManager.differsFromLive)
  property bool canReset: true
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
    kind: "primary"
    iconText: "check"
    label: root.saveLabel
    onClicked: {
      EditsManager.commitTyping();
      root.save();
    }
  }

  ActionButton {
    id: resetButton
    visible: (root.dirty && root.canReset) || root._typing
    kind: "text"
    iconText: "undo"
    label: I18n.tr("Discard")
    onClicked: {
      EditsManager.discardTyping();
      root.reset();
    }
  }

  // Sized to its label (translations differ in width, and fonts in height),
  // at least `minWidth` so Save and Discard line up in English; compact, the
  // icon alone with the label as its tooltip
  component ActionButton: StyledTextButton {
    id: button

    property string label
    readonly property int minWidth: Widget.textPx(80)
    // With the label, whatever `compact` is: the label and icon measured
    // here, as the button lays them out
    readonly property real fullWidth: Math.max(button.minWidth, Math.ceil(labelMetrics.advanceWidth) + Math.ceil(iconMetrics.advanceWidth) + Widget.spacing / 2 + button.textPadding * 2)

    text: root.compact ? "" : button.label
    tooltipText: root.compact ? button.label : ""
    opacity: button.enabled ? 1 : Style.opacityDisabled
    Layout.preferredWidth: root.compact ? button.implicitHeight : button.fullWidth
    Layout.preferredHeight: Widget.height

    TextMetrics {
      id: labelMetrics
      font.family: Appearance.fontFamily
      font.pixelSize: button.textSize
      font.weight: Style.roleLabel.weight
      text: button.label
    }
    TextMetrics {
      id: iconMetrics
      font.family: Appearance.iconFamily
      font.pixelSize: button.textSize
      text: button.iconText
    }
  }
}
