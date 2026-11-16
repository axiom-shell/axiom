pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// The fold row of every card, on the settings page and in the editors: a
// FoldHeader in a FormRow. SettingsField builds on it (its `x-fold` and
// `x-intro` Settings rows set `fold`; the others draw no header), and
// FoldingCard reads `shutFold` to close a card that ends on a shut one. The
// host owns `open` (a plain property); the rows behind it are its siblings
// with `shown: open && …`, each keeping its own tree level (a fold is not a
// dependency: no indent, no rail).
FormRow {
  id: root

  property string title
  // Whether the rows behind it show
  property bool open: false
  // False: the header doesn't fold it (search results)
  property bool foldable: true
  // An unsaved edit behind it (the dot, while shut)
  property bool marked: false
  // False: this row is not a fold row and draws no header (a SettingsField
  // for a value)
  property bool fold: true
  // The header's height, 0 while this isn't a fold row
  readonly property real foldHeight: root.fold ? header.implicitHeight : 0
  // A fold row with its rows hidden: what ends a card with no padding of its own
  readonly property bool shutFold: root.fold && !root.open

  signal toggled

  tinted: false
  hoverable: false
  bodyHeight: root.foldHeight
  railHeight: 0

  Loader {
    id: header
    active: root.fold
    width: parent.width

    sourceComponent: FoldHeader {
      title: root.title
      collapsed: !root.open
      foldable: root.foldable
      marked: root.marked
      // The trigger is the row's band, as a tinted row's
      reachTop: (root.fullHeight - root.bodyHeight) / 2
      reachBottom: (root.fullHeight - root.bodyHeight) / 2
      reachLeft: root.depth > 0 ? root.step : Style.rowBleed
      reachRight: Style.rowBleed
      onToggled: root.toggled()
    }
  }
}
