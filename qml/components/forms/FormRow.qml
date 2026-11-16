pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.methods

// One row of a schema form (the settings page, an editor's options, the
// onboarder), a row of the boxed list: padded `Style.rowPadding` above and
// below, at least `Style.rowHeight` tall, a divider on its top boundary
// (none on the top row), an accent rail beside a row shown by a sibling's
// value, and a fold open and shut as its `x-showIf` shows or hides it, so
// the rows below glide. Its depth is `level`, its place in its form's
// RowTree (SchemaPropertiesForm, SettingsGroupCard) or, for a hand-built row,
// its own: one rail per depth, the body one step in per depth, and the hover
// tint starting at the row's own innermost rule. A `tinted` row (the default) tints under the
// pointer, and keeps the tint while the pointer is over its controls: the
// HoverHandler is on the row, an ancestor of every control (a handler on a
// sibling painted under them loses the hover to any child that takes it).
// A `hoverable` row also acts on a click outside its controls
// (`rowClicked`). The tint and the click cover the band: the whole row, or
// with a `hitHeight` shorter than the body, the first `hitHeight` of it
// padded below by as much as above, so the field sits centred in it. What
// the row holds sits in its body.
Item {
  id: root

  // Whether the row shows; undefined while that isn't known (a field still
  // streaming in), which takes its height at once instead of folding
  property var shown: true
  // How deep the row sits: its dependency chain in its form (RowTree), 0 for
  // none; a hand-built row under another sets 1
  property int level: 0
  // The right half of a pair: draws no rails and no indent, its left half does
  property bool beside: false
  readonly property int depth: root.beside ? 0 : root.level
  // The content's height, and how much of it the rail runs beside
  property real bodyHeight: 0
  property real railHeight: root.bodyHeight
  // The part of the body, from its top, that a row click and the hover tint cover; the rest takes no row click
  property real hitHeight: root.bodyHeight
  // Whether the row tints under the pointer
  property bool tinted: true
  // Whether a click on the row outside its controls is `rowClicked`
  // (pointing cursor); a hoverable row always tints
  property bool hoverable: false
  // The pointer is over the row's band
  readonly property bool hovered: rowHover.hovered && rowHover.point.position.y < band.height
  // The form's top row (no row above it shown), which has no gap: set by
  // the host (Utils.firstFormRow), never read from `y`, which the
  // layout sets from this row's height (a row flipping between the two
  // kept the layout polishing forever)
  property bool first: false
  default property alias content: body.data
  readonly property real step: Widget.spacing * 2
  readonly property real indent: root.depth * root.step
  // The row at full reveal: its body padded, no less than a row's height
  // (none for an empty row, a field drawing nothing)
  readonly property real fullHeight: root.bodyHeight <= 0 ? 0 : Math.max(Style.rowHeight, root.bodyHeight + Style.rowPadding * 2)

  // A click on the row outside its controls (while `hoverable`)
  signal rowClicked

  // A relay: the walks of the texts in the row stop here
  readonly property var inkHostAbove: InkHost.find(root.parent)
  readonly property real drawnZoom: TextRender.zoomAt(root.parent)

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
  implicitHeight: root.fullHeight * root._reveal
  visible: root._reveal > 0
  clip: root._reveal < 1

  HoverHandler {
    id: rowHover
    enabled: root.tinted || root.hoverable
  }

  // The hover tint and the row click, built while tinted or hoverable.
  // Under the body, so a control takes its own clicks
  Loader {
    id: band
    // From the row's own rule below depth 0, else the full width
    x: root.depth > 0 ? (root.depth - 1) * root.step : 0
    width: root.width - band.x
    height: root.hitHeight >= root.bodyHeight ? root.height : Math.min(root.height, root.hitHeight + body.y * 2)
    active: root.tinted || root.hoverable
    sourceComponent: Item {
      StateLayer {
        objectName: "rowTint"
        bleed: Style.rowBleed
        leftBleed: root.depth > 0 ? 0 : Style.rowBleed
        hovered: root.hovered
        pressed: click.pressed
      }

      // Invisible, it takes no clicks and sets no cursor
      MouseArea {
        id: click
        anchors.fill: parent
        visible: root.hoverable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.rowClicked()
      }
    }
  }

  // On the row's top boundary, over the tint
  StyledSeparator {
    visible: !root.first && root.fullHeight > 0
    x: root.indent
    width: Math.max(0, root.width - root.indent)
  }

  // One rail per depth, each beside the next step in
  Repeater {
    model: root.depth

    Rectangle {
      required property int index
      x: index * root.step
      y: body.y
      width: 2
      height: root.railHeight
      radius: 1
      color: Style.rail
      opacity: root._reveal
    }
  }

  Item {
    id: body
    x: root.indent
    y: Math.round((root.fullHeight - root.bodyHeight) / 2)
    width: Math.max(0, root.width - root.indent)
    height: root.bodyHeight
    opacity: root._reveal
  }
}
