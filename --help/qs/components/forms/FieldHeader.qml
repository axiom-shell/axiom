pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions)
// A form field's label with its description right under it, read as one
// unit above (or beside) the field's control
ColumnLayout {
  id: root
  property string label: ""
  property string description: ""
  // Shown right after the label, on its line (the settings row's unsaved
  // dot and reset button)
  property Component trailing: null
  // A list's title: bold and a step larger
  property bool title: false
  readonly property real _trailingRoom: trailingPart.active ? trailingPart.implicitWidth + Widget.spacing : 0

  Layout.fillWidth: true
  spacing: Widget.px(2)
  visible: root.label !== "" || root.description !== ""

  // The label at its one-line width, or what's left beside the trailing
  // part: it wraps, never elides. (Placed by hand: a layout sizing the
  // label from its own width rearranges recursively.)
  Item {
    id: labelRow
    visible: root.label !== ""
    Layout.fillWidth: true
    implicitWidth: Math.ceil(labelWidth.advanceWidth) + 1 + root._trailingRoom
    implicitHeight: labelText.height

    StyledText {
      id: labelText
      width: Math.max(0, Math.min(Math.ceil(labelWidth.advanceWidth) + 1, labelRow.width - root._trailingRoom))
      text: I18n.tr(root.label)
      textSize: root.title ? Appearance.fontSizeBy(1) : Appearance.fontSize
      font.weight: root.title ? Font.Bold : Font.Medium
      wrapMode: Text.Wrap
    }

    // Centred on the label, whatever it shows
    Loader {
      id: trailingPart
      x: labelText.width + Widget.spacing
      height: labelText.height
      active: root.trailing !== null
      sourceComponent: root.trailing
    }
  }

  TextMetrics {
    id: labelWidth
    font: labelText.font
    text: labelText.text
  }

  // Long help folds to three lines behind More
  ClampedText {
    text: root.description === "" ? "" : I18n.tr(root.description)
  }
}
