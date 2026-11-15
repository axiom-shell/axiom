pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config

// One entry of an editor's list (bars, overlay pages, edge menus): an
// icon and a name, filled with the accent container while selected, then
// `badges`, the unsaved-edits dot, an `issue` mark and the row's actions
// (RowActions, as children), which show while the row is hovered, focused or
// selected. `leading` is a slot before the icon (a switch, keycaps) and a
// `subtitle` follows the name on its line.
// A tap is `clicked`; with `dragArea.dragLayer` and `payload` set, the row
// can also be carried. It takes keyboard focus (one Tab stop for the whole
// list: Tab goes through the row's leading controls and actions, then out of the list): Up and
// Down move to the previous and next row, Enter is `clicked`, Delete
// `removeRequested` and Escape, while the row is selected and the page set `escapeClears`, `escapePressed`
// (the page runs the remove, with its own blocked rule, and clears its
// selection).
Rectangle {
  id: root

  property string icon
  property string label
  property bool selected: false
  // A disabled entry: its name is dimmed
  property bool dimmed: false
  // Unsaved edits
  property bool changed: false
  // A line after the name (at most a quarter of the row); empty shows none
  property string subtitle: ""
  property int subtitleLines: 1
  // "" | "error" | "warning" | "info": an IssueIcon before the actions,
  // saying `issueTip` on hover
  property string issue: ""
  property string issueTip: ""
  // The name struck through (a switched-off entry that still counts)
  property bool strikeout: false
  // The page clears its selection on Escape (it connects escapePressed); otherwise Escape reaches the host (an overlay closes)
  property bool escapeClears: false
  property alias leading: leadingRow.data
  property alias badges: badgeRow.data
  default property alias actions: actionRow.data
  property alias dragArea: area

  // A HoverHandler, not the drag area's containsMouse, so the row stays
  // hovered while the pointer is on one of its actions
  readonly property bool hovered: hover.hovered
  // The colour of text and icons on the row
  readonly property color ink: root.selected ? Style.inkAccentContainer.text : root.dimmed ? Style.textFaint : Style.text
  // The colour of a sub-line on the row
  readonly property color inkMuted: root.selected ? Style.inkAccentContainer.muted : Style.textMuted
  // Whether the row's actions show: hovered, focused or selected, or one of
  // them focused
  readonly property bool revealed: root.hovered || root.selected || root.activeFocus || root._actionFocused

  readonly property bool _actionFocused: actionRow.children.some(child => child.activeFocus)

  // Marks a row for the Up/Down walk along the focus chain
  readonly property bool _listRow: true

  signal clicked
  signal removeRequested
  signal escapePressed

  // The row at the end of `item`'s ancestry that is a list row, or null
  function _rowOf(item) {
    for (let it = item; it; it = it.parent)
      if (it._listRow === true)
        return it;
    return null;
  }

  // True when `item` sits inside a list header (ListSection marks it)
  function _inHeader(item) {
    for (let it = item; it; it = it.parent)
      if (it._listHeader === true)
        return true;
    return false;
  }

  // The next list row from this one along the focus chain (`forward`), the
  // actions inside rows and the controls of a section header skipped; null at
  // anything else that is not a row
  function _neighbour(forward) {
    let it = root;
    for (let i = 0; i < 200; i++) {
      it = it.nextItemInFocusChain(forward);
      if (!it || it === root)
        return null;
      const owner = root._rowOf(it);
      if (owner === root)
        continue;
      if (owner === null && root._inHeader(it))
        continue;
      return owner;
    }
    return null;
  }

  // Focus moves out of the list: to the first item past its rows, forward or
  // back, never the next row
  function _leave(forward) {
    let it = root;
    for (let i = 0; i < 400; i++) {
      it = it.nextItemInFocusChain(forward);
      if (!it || it === root)
        return;
      if (root._rowOf(it) === null) {
        it.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        return;
      }
    }
  }

  // Tab (`forward`) or Shift+Tab pressed on `from` (this row, or one of its
  // actions or leading controls): the next or previous stop of this row (its
  // leading controls, then its actions), else out
  function _tabFrom(from, forward) {
    const actions = leadingRow.children.concat(actionRow.children).filter(child => child.visible && child.enabled && child.activeFocusOnTab);
    const at = actions.indexOf(from);
    const next = forward ? actions[at + 1] : at > 0 ? actions[at - 1] : (at === 0 ? root : undefined);
    if (next) {
      next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
      return;
    }
    root._leave(forward);
  }

  activeFocusOnTab: true
  Keys.onTabPressed: root._tabFrom(root, true)
  Keys.onBacktabPressed: root._tabFrom(root, false)
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
      const next = root._neighbour(event.key === Qt.Key_Down);
      if (next)
        next.forceActiveFocus(Qt.TabFocusReason);
      event.accepted = next !== null;
    } else if (event.key === Qt.Key_Escape && root.selected && root.escapeClears) {
      root.escapePressed();
      event.accepted = true;
    } else if (root.activeFocus && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      root.clicked();
      event.accepted = true;
    } else if (root.activeFocus && event.key === Qt.Key_Delete) {
      root.removeRequested();
      event.accepted = true;
    }
  }

  Layout.fillWidth: true
  Layout.preferredHeight: Widget.height + Widget.padding
  color: root.selected ? Style.accentContainer : Qt.alpha(Style.accentContainer, 0) // style-exempt: the selected fill at no alpha, so deselecting doesn't fade through black
  radius: Style.radius

  ColorGlide on color {
    duration: Appearance.animNormal
  }

  StateLayer {
    hovered: root.hovered
    dragged: area.dragged
  }

  HoverHandler {
    id: hover
  }

  FocusRing {
    shown: root.activeFocus
  }

  DragArea {
    id: area
    anchors.fill: parent
    dragEnabled: area.dragLayer !== null
    onTapped: root.clicked()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Widget.padding
    anchors.rightMargin: Widget.padding / 2
    spacing: Widget.spacing

    RowLayout {
      id: leadingRow
      visible: children.length > 0
      spacing: Widget.spacing
    }

    StyledIcon {
      text: root.icon
      textColor: root.selected ? Style.inkAccentContainer.icon : root.dimmed ? Style.textFaint : Style.textAccent
      Layout.preferredWidth: Style.iconSm * 1.5
    }

    StyledLabel {
      id: name

      text: root.label
      role: "label"
      overflow: "line"
      textColor: root.ink
      font.strikeout: root.strikeout
      Layout.fillWidth: true
    }

    // Built only while there is a subtitle, so a row without one pays nothing
    Loader {
      active: root.subtitle !== ""
      visible: active
      Layout.maximumWidth: root.width * 0.25
      sourceComponent: StyledLabel {
        text: root.subtitle
        role: "caption"
        overflow: root.subtitleLines > 1 ? "wrap" : "line"
        maxLines: root.subtitleLines
        textColor: root.inkMuted
      }
    }

    RowLayout {
      id: badgeRow
      spacing: Widget.spacing
    }

    UnsavedDot {
      shown: root.changed
      onAccent: root.selected
    }

    // Built only while there is an issue
    Loader {
      active: root.issue !== ""
      visible: active
      sourceComponent: IssueIcon {
        id: issueIcon

        level: root.issue
        tip: root.issueTip
        size: "sm"
        textColor: root.selected ? Style.inkAccentContainer.text : Style.toneColor(issueIcon.tone)
      }
    }

    RowLayout {
      id: actionRow
      spacing: Widget.spacing
    }
  }

  // The full name of an elided label
  LazyLoader {
    active: hover.hovered && name.truncated
    StyledToolTip {
      target: name
      text: root.label
    }
  }
}
