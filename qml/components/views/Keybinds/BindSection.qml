pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.views.base

// A section of the Keybinds editor's list (KeybindManager.page.editLayout): a
// ListSection whose header folds it (remembered, EditsManager.keybindsFolded)
// and ends in its issue mark and count, the unsaved dot and a switch pausing
// or resuming all of it, over its rows (BindListRow, a run's binds under it
// while unfolded). Rows carried within the section drop here (a drag layer
// target).
ListSection {
  id: root

  // { key, indices, rows: [[index]] }
  required property var section
  property var dragLayer: null
  property var scrollTo: null

  readonly property bool folded: EditsManager.keybindsFolded.includes(root.section.key)
  readonly property bool allPaused: root.section.indices.every(i => KeybindManager.editor.binds[i]?.paused === true)
  readonly property int issueCount: root.section.indices.filter(i => KeybindManager.editor.hasIssue(KeybindManager.editor.issues[i])).length
  readonly property bool changed: root.section.indices.some(i => KeybindManager.editor.changedBinds[i] === true)

  // As a drop target: rows carried within the section, dropped before the
  // row under the pointer
  readonly property string targetKind: "bindSection"
  readonly property bool hovered: root.dragLayer !== null && root.dragLayer.hoverTarget === root

  function takes(index) {
    return !root.folded && root.section.indices.includes(index);
  }

  // The row position a drop at `point` (in the drag layer) goes before
  function indexAt(point) {
    const p = root.dragLayer.mapToItem(rowStack, point.x, point.y);
    for (let i = 0; i < rowRepeater.count; i++) {
      const row = rowRepeater.itemAt(i);
      if (row && p.y < row.y + row.height / 2)
        return i;
    }
    return rowRepeater.count;
  }

  // Moves bind `from` before the row at `position` (the end past the last)
  function dropAt(from, position) {
    const rowList = root.section.rows;
    let to;
    if (position < rowList.length) {
      const before = Math.min(...rowList[position]);
      to = from < before ? before - 1 : before;
    } else {
      const last = Math.max(...root.section.indices);
      to = from < last ? last : last + 1;
    }
    KeybindManager.editor.moveBind(from, Math.min(to, KeybindManager.editor.binds.length - 1));
  }

  // Section names come from BindActions.sectionFor (or a bind's own
  // "Section:" description)
  title: I18n.tr(root.section.key)
  count: root.section.indices.length
  collapsible: true
  open: !root.folded
  onToggled: EditsManager.setKeybindsFolded(root.section.key, !root.folded)

  trailing: [
    IssueIcon {
      visible: root.issueCount > 0
      tip: KeybindManager.editor.issueTip(root.section.indices)
      size: "sm"
    },
    StyledText {
      visible: root.issueCount > 0
      text: root.issueCount
      role: "caption"
      tone: "warning"
    },
    UnsavedDot {
      shown: root.changed
    },
    StyledText {
      text: root.allPaused ? I18n.tr("Paused") : ""
      role: "caption"
      tone: "faint"
    },
    // Pauses or resumes the whole section
    StyledSwitch {
      compact: true
      checkable: false
      checked: !root.allPaused
      onClicked: KeybindManager.editor.setPaused(root.section.indices, !root.allPaused)
    }
  ]

  Component.onCompleted: {
    if (root.dragLayer)
      root.dragLayer.registerTarget(root);
  }
  Component.onDestruction: {
    if (root.dragLayer)
      root.dragLayer.unregisterTarget(root);
  }

  // Unfolds to show a bind asked for
  Connections {
    target: KeybindManager.editor

    function onRevealRequested(index) {
      if (root.section.indices.includes(index) && root.folded)
        EditsManager.setKeybindsFolded(root.section.key, false);
    }
  }

  ColumnLayout {
    id: rowStack
    Layout.fillWidth: true
    spacing: 2

    Repeater {
      id: rowRepeater
      model: root.section.rows

      delegate: ColumnLayout {
        id: rowItem
        required property var modelData
        Layout.fillWidth: true
        spacing: 2

        BindListRow {
          id: head
          indices: rowItem.modelData
          dragLayer: root.dragLayer
          scrollTo: root.scrollTo
        }

        // A run's binds, while it's unfolded
        Repeater {
          model: head.isRun && head.expanded ? rowItem.modelData : []

          delegate: BindListRow {
            required property int modelData
            indices: [modelData]
            nested: true
            scrollTo: root.scrollTo
          }
        }
      }
    }
  }

  // Where a carried row would land (always in the layout, taking no room,
  // so showing it moves nothing)
  Item {
    Layout.fillWidth: true
    Layout.preferredHeight: 0
    z: 2

    Rectangle {
      visible: root.hovered && root.dragLayer.hoverIndex >= 0
      readonly property var target: rowRepeater.itemAt(Math.min(root.dragLayer?.hoverIndex ?? 0, rowRepeater.count - 1))
      readonly property real at: !target ? 0 : (root.dragLayer.hoverIndex >= rowRepeater.count ? target.y + target.height : target.y)
      width: parent.width
      height: Widget.px(3)
      radius: 1.5
      y: rowStack.y + at - 1.5 - parent.y
      color: Style.accent
    }
  }
}
