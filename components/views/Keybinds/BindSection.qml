pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable

// A section of the Keybinds editor's list (KeybindManager.page.editLayout): a
// header to fold it (remembered, EditsManager.keybindsFolded), with its
// counts, the unsaved dot and a switch pausing or resuming all of it, over
// its rows (BindListRow, a run's binds under it while unfolded). Rows
// carried within the section drop here (a drag layer target).
ColumnLayout {
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
    const p = root.dragLayer.mapToItem(rows, point.x, point.y);
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

  Layout.fillWidth: true
  spacing: Widget.spacing / 2

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

  Item {
    Layout.fillWidth: true
    implicitHeight: Widget.height

    MouseArea {
      id: headerArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: EditsManager.setKeybindsFolded(root.section.key, !root.folded)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Widget.padding / 2
      anchors.rightMargin: Widget.padding / 2
      spacing: Widget.spacing

      StyledIcon {
        text: "expand_more"
        textColor: headerArea.containsMouse ? Theme.accent : Theme.foregroundAlt
        rotation: root.folded ? -90 : 0

        Glide on rotation {}
      }

      StyledText {
        // Section names come from BindActions.sectionFor (or a bind's own
        // "Section:" description)
        text: I18n.tr(root.section.key)
        textColor: Theme.accent
        font.bold: true
      }

      StyledText {
        text: root.section.indices.length
        opacity: 0.5
        textSize: Appearance.fontSizeBy(-2)
      }

      // What's wrong in the section, each problem once
      IssueIcon {
        visible: root.issueCount > 0
        tip: visible ? [...new Set([].concat(...root.section.indices.map(i => KeybindManager.editor.issues[i] ?? [])).filter(issue => issue.level !== "info").map(issue => issue.text))].join("\n") : ""
        textSize: Appearance.fontSizeBy(-1)
      }

      StyledText {
        visible: root.issueCount > 0
        text: root.issueCount
        textColor: Theme.warning
        textSize: Appearance.fontSizeBy(-2)
      }

      UnsavedDot {
        shown: root.changed
      }

      Item {
        Layout.fillWidth: true
      }

      StyledText {
        text: root.allPaused ? I18n.tr("Paused") : ""
        opacity: 0.5
        textSize: Appearance.fontSizeBy(-2)
      }

      // Pauses or resumes the whole section
      StyledSwitch {
        checkable: false
        checked: !root.allPaused
        implicitHeight: Widget.smallHeight
        onClicked: KeybindManager.editor.setPaused(root.section.indices, !root.allPaused)
      }
    }
  }

  ColumnLayout {
    id: rows
    visible: !root.folded
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
      y: rows.y + at - 1.5 - parent.y
      color: Theme.accent
    }
  }
}
