pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A box inside a card that holds one item (a list entry, the selected item
// of an editor, notes, an import): a sunken Surface. Padded as the style says:
// `Widget.padding` all round, or for a `dense` one-line item `Widget.padding`
// left and right and `Widget.smallPadding` above and below. With a `title` it
// has a header: an accent `icon`, the title, a faint `caption`, `headerActions`
// (a slot) and, while `removable`, a close button (`remove`). With `foldable`
// the header folds the body: a click is `toggled` (the host flips `open`,
// as FoldHeader), and `summary` is the one line it shows while folded. What
// the box holds goes in its default slot, a column spaced `bodySpacing` that
// is a FormColumn (a FormRow in it gets its `first` from it).
Surface {
  id: root

  // -- Public API --
  property string icon: ""
  // The header shows while this is set
  property string title: ""
  property string caption: ""
  // The one-line item: smaller padding above and below
  property bool dense: false
  // A close button at the header's end
  property bool removable: false
  property string removeTooltip: I18n.tr("Remove")
  // The header folds the body (shows a chevron, is a Tab stop)
  property bool foldable: false
  property bool open: true
  // The line shown under the header while folded
  property string summary: ""
  // The body's spacing: 0 for a box of FormRows (they pad themselves)
  property alias bodySpacing: fold.spacing
  property alias headerActions: actionRow.data
  default property alias content: fold.content
  readonly property bool hasHeader: root.title !== ""

  signal remove
  signal toggled

  // -- Implementation --
  readonly property real _sidePad: Widget.padding
  readonly property real _vertPad: root.dense ? Widget.smallPadding : Widget.padding
  readonly property bool _folded: root.foldable && !root.open

  Layout.fillWidth: true
  tone: "sunken"
  implicitHeight: column.implicitHeight + root._vertPad * 2

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.leftMargin: root._sidePad
    anchors.rightMargin: root._sidePad
    anchors.topMargin: root._vertPad
    anchors.bottomMargin: root._vertPad
    spacing: 0

    Item {
      id: header
      visible: root.hasHeader
      Layout.fillWidth: true
      implicitHeight: headerRow.implicitHeight
      // The trigger tints as the box
      readonly property real radius: root.radius

      // The whole header is the fold trigger (a button), reaching the box's
      // padding; open, down to the body, bottom square
      Pressable {
        id: press
        objectName: "foldTrigger"
        enabled: root.foldable
        tabStop: root.foldable
        squareBottom: !root._folded
        anchors.leftMargin: -root._sidePad
        anchors.rightMargin: -root._sidePad
        anchors.topMargin: -root._vertPad
        anchors.bottomMargin: root._folded ? -(root.height - root._vertPad - header.height) : -fold.topPadding
        onClicked: root.toggled()
      }

      RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Widget.spacing

        StyledIcon {
          visible: root.icon !== ""
          text: root.icon
          tone: "accent"
        }

        StyledLabel {
          Layout.fillWidth: true
          text: root.title
          role: "label"
          overflow: "line"
        }

        StyledLabel {
          visible: root.caption !== ""
          text: root.caption
          role: "caption"
          tone: "faint"
          overflow: "line"
          Layout.maximumWidth: root.width * 0.4
        }

        RowLayout {
          id: actionRow
          visible: children.length > 0
          spacing: Widget.spacing
        }

        StyledIconButton {
          visible: root.removable
          kind: "danger"
          size: Widget.compactHeight
          iconText: "close"
          tooltipText: root.removeTooltip
          onClicked: root.remove()
        }

        FoldChevron {
          visible: root.foldable
          open: root.open
          hot: press.hovered || press.activeFocus
        }
      }
    }

    StyledLabel {
      visible: root._folded && root.summary !== ""
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing / 2
      text: root.summary
      role: "caption"
      tone: "muted"
      overflow: "line"
    }

    FoldingColumn {
      id: fold
      open: !root.foldable || root.open
      topPadding: root.hasHeader && fold.contentChildren.length > 0 ? Widget.spacing : 0
      spacing: Widget.spacing
      Layout.fillWidth: true
    }
  }
}
