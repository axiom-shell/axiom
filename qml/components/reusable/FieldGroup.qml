pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.components.methods

// The settings page's card, for an editor's group of fields: a FoldingCard
// (header with the title, description and chevron at the top), rows indented
// only by RowTree, a fold row (FoldFormRow) for extra options; a title-less
// card doesn't fold and has a header only for a description (the selection's
// own identity rows, OptionsGroup). The fold is the card's own `collapsed` (open whenever the card
// is built, never saved); a host that must stay visible sets `foldable: false`.
// Children stack with no gap, as a settings card's rows do (a row pads itself,
// FormRow); a non-row child that follows another takes its own
// `Layout.topMargin: Style.space2`. A card whose rows are all hidden hides
// itself: only its direct children count, a form (`allHidden`) or a FormRow
// (`shown`), never anything's `visible` or height.
FoldingCard {
  id: root

  headed: root.title !== "" || root.description !== ""
  foldable: root.title !== ""
  bodySpacing: 0
  onToggled: root.collapsed = !root.collapsed

  // Every counted child hidden (FormRows.empty: a form's `allHidden`, a
  // row's `shown`); other children don't count, nor does a card with none
  readonly property bool _empty: FormRows.empty(root.contentChildren)

  // Restores the host's own `visible` when the rows return
  Binding {
    target: root
    property: "visible"
    value: false
    when: root._empty
  }

  Layout.alignment: Qt.AlignTop
}
