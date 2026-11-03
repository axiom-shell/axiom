pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// One row of a schema form (the settings page, an editor's options, the
// onboarder): a hairline across the gap above it (none on the top row), an
// accent rail beside a row shown by a sibling's value, and a fold open and
// shut as its `x-showIf` shows or hides it, gap and all, so the rows below
// glide. What it holds sits in its body, under the gap.
Item {
  id: root

  // Whether the row shows; undefined while that isn't known (a field still
  // streaming in), which takes its height at once instead of folding
  property var shown: true
  // On the rail, read as part of the row above (a part's fields under its
  // switch: SchemaField.followsSibling)
  property bool indented: false
  // The content's height, and how much of it the rail runs beside
  property real bodyHeight: 0
  property real railHeight: root.bodyHeight
  // The gap above the row, kept inside the row's height so it folds too
  property real dividerGap: Widget.spacing * 3
  // The form's top row (no row above it shown), which has no gap: set by
  // the host (Utils.firstFormRow), never read from `y`, which the
  // layout sets from this row's height (a row flipping between the two
  // kept the layout polishing forever)
  property bool first: false
  default property alias content: body.data
  readonly property real indent: root.indented ? Widget.spacing * 2 : 0
  // None above an empty row either (a field drawing nothing)
  readonly property real topGap: root.first || root.bodyHeight <= 0 ? 0 : root.dividerGap

  // 1 shown, 0 hidden. Set by hand, not bound: a binding and the fold
  // would both answer a change of `shown`, in no set order
  property real _reveal: 0
  property bool _known: false
  Component.onCompleted: {
    root._reveal = root.shown === true ? 1 : 0;
    root._known = root.shown !== undefined;
  }
  onShownChanged: {
    const to = root.shown === true ? 1 : 0;
    if (root._known && root.shown !== undefined) {
      fold.to = to;
      fold.restart();
    } else {
      fold.stop();
      root._reveal = to;
    }
    root._known = root.shown !== undefined;
  }

  NumberAnimation {
    id: fold
    target: root
    property: "_reveal"
    duration: Appearance.animFast
    easing.type: Appearance.easing
  }

  Layout.fillWidth: true
  implicitHeight: (root.topGap + root.bodyHeight) * root._reveal
  visible: root._reveal > 0
  clip: root._reveal < 1

  StyledSeparator {
    visible: root.topGap > 0
    x: root.indent
    y: Math.round(root.topGap / 2) - 1
    width: root.width - root.indent
    separatorHeight: 1
    opacity: 0.45
  }

  Rectangle {
    visible: root.indented
    y: root.topGap
    width: 2
    height: root.railHeight
    radius: 1
    color: Theme.accent
    opacity: 0.35 * root._reveal
  }

  Item {
    id: body
    x: root.indent
    y: root.topGap
    width: root.width - root.indent
    height: root.bodyHeight
    opacity: root._reveal
  }
}
