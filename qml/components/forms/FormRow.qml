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
// the rows below glide. A `hoverable` row (a switch, a two-option toggle, a
// dropdown) acts on a click anywhere on it (`rowClicked`) and tints under
// the pointer. What it holds sits in its body.
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
  // The part of the body, from its top, that a row click and the hover tint cover; the rest takes no row click
  property real hitHeight: root.bodyHeight
  // Whether the whole row acts: it tints under the pointer and a click on
  // it outside its controls is `rowClicked`
  property bool hoverable: false
  // The form's top row (no row above it shown), which has no gap: set by
  // the host (Utils.firstFormRow), never read from `y`, which the
  // layout sets from this row's height (a row flipping between the two
  // kept the layout polishing forever)
  property bool first: false
  default property alias content: body.data
  readonly property real indent: root.indented ? Widget.spacing * 2 : 0
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

  // The hover tint and the row click, built only while hoverable. Under the
  // body, so a control takes its own clicks
  Loader {
    width: root.width
    height: root.hitHeight >= root.bodyHeight ? root.height : body.y + root.hitHeight
    active: root.hoverable
    sourceComponent: Item {
      StateLayer {
        bleed: Style.rowBleed
        hovered: hover.hovered
        pressed: click.pressed
      }

      HoverHandler {
        id: hover
      }

      MouseArea {
        id: click
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.rowClicked()
      }
    }
  }

  // On the row's top boundary, over the tint
  StyledSeparator {
    visible: !root.first && root.fullHeight > 0
    x: root.indent
    width: root.width - root.indent
  }

  Rectangle {
    visible: root.indented
    y: body.y
    width: 2
    height: root.railHeight
    radius: 1
    color: Style.rail
    opacity: root._reveal
  }

  Item {
    id: body
    x: root.indent
    y: Math.round((root.fullHeight - root.bodyHeight) / 2)
    width: root.width - root.indent
    height: root.bodyHeight
    opacity: root._reveal
  }
}
