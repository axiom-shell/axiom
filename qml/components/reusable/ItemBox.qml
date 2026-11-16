pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.methods

// A box inside a card that holds one item (a list entry, the selected item
// of an editor, notes, an import): a sunken Surface. Padded as the style says:
// `Widget.padding` all round, or for a `dense` one-line item `Widget.padding`
// left and right and `Widget.smallPadding` above and below. With a `title` it
// has a header: an accent `icon`, the title, a faint `caption`, `headerActions`
// (a slot) and, while `removable`, a close button (`remove`). With `foldable`
// the header folds the body: a click is `toggled` (the host flips `open`,
// as FoldHeader), and `summary` is the one line it shows while folded. What
// the box holds goes in its default slot, a column spaced `Widget.spacing`
// that publishes `firstRow` (a FormRow in it takes it for its `first`).
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
  property alias headerActions: actionRow.data
  default property alias content: fold.content
  // The first row of the body that draws something (no divider on it)
  readonly property Item firstRow: {
    const at = Utils.firstFormRow(fold.contentChildren.length, i => fold.contentChildren[i]);
    return at < 0 ? null : fold.contentChildren[at];
  }
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
      activeFocusOnTab: root.foldable

      Keys.onSpacePressed: event => header._key(event)
      Keys.onReturnPressed: event => header._key(event)
      Keys.onEnterPressed: event => header._key(event)

      function _key(event) {
        event.accepted = root.foldable;
        if (root.foldable)
          root.toggled();
      }

      FocusRing {
        shown: header.activeFocus
      }

      MouseArea {
        id: headerArea
        anchors.fill: parent
        enabled: root.foldable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
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
          hot: headerArea.containsMouse || header.activeFocus
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
