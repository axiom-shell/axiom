pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A form field's label with its description right under it, read as one
// unit above (or beside) the field's control
ColumnLayout {
  id: root
  property string label: ""
  property string description: ""
  // Shown right after the label, on its line (the settings row's unsaved
  // dot and reset button)
  property Component trailing: null
  // Shown under the description, read with the label (a field's `x-link`
  // line). Its root declares `readonly property bool shows`, from data
  // (never layout)
  property Component below: null
  // A list's title: the title role, a step larger
  property bool title: false
  readonly property real _trailingRoom: trailingPart.active ? trailingPart.implicitWidth + Widget.spacing : 0
  // The label's line at one line with the trailing part at its widest (a
  // constant: never `truncated` or a laid-out width), 0 without a label:
  // what FieldFit places a field by
  readonly property var _trailingItem: trailingPart.item
  readonly property real lineWidth: root.label === "" ? 0 : Math.ceil(labelWidth.advanceWidth) + 1 + (trailingPart.active ? (root._trailingItem?.fullWidth ?? trailingPart.implicitWidth) + Widget.spacing : 0)

  Layout.fillWidth: true
  spacing: Widget.px(2)
  // (`item.shows`, never `belowPart.visible`: that depends on this one)
  readonly property var _belowItem: belowPart.item
  readonly property bool _belowShows: root._belowItem?.shows === true
  // Something to show (what `visible` follows)
  readonly property bool hasContent: root.label !== "" || root.description !== "" || root._belowShows
  visible: root.hasContent

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
      role: root.title ? "title" : "label"
      overflow: "wrap"
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

  Loader {
    id: belowPart
    Layout.fillWidth: true
    Layout.topMargin: Widget.spacing / 2
    active: root.below !== null
    visible: root._belowShows
    sourceComponent: root.below
  }
}
