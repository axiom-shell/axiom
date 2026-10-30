pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// The todo list (TodoManager), for the Todo popout and module and the
// Focus module: a field to add one, then the items (open, then done with
// Todo.showCompleted). Clicking an item ticks it off or reopens it; on
// hover, rename, work on it (the pomodoro's task, starting the timer) and
// delete. `fill` takes the height it's given (a card); otherwise it sizes
// to its rows, up to `maxListHeight` (a popout).
ColumnLayout {
  id: root

  property bool fill: false
  property real maxListHeight: Number.POSITIVE_INFINITY
  // The work-on-it button (off where no timer is near)
  property bool showFocus: true
  // The item being renamed ("" for none)
  property string editing: ""
  // The field last, below the items (a popout growing up: Panel.growth)
  property bool reversed: false
  property LayoutOrder _order: LayoutOrder {
    layout: root
    reversed: root.reversed
  }
  readonly property var items: TodoManager.shownItems

  spacing: Widget.spacing / 2

  function rename(uid, text) {
    TodoManager.rename(uid, text);
    root.editing = "";
  }

  StyledTextEntry {
    id: addField
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height
    placeholderText: I18n.tr("Add a todo")
    onAccepted: {
      if (TodoManager.add(addField.text) !== "")
        addField.text = "";
    }
  }

  Flickable {
    id: flick
    visible: root.items.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: root.fill
    Layout.preferredHeight: root.fill ? -1 : Math.min(rows.implicitHeight, root.maxListHeight)
    contentHeight: rows.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
      id: rows
      width: flick.width
      spacing: 0

      Repeater {
        model: root.items.length

        delegate: ColumnLayout {
          id: entry
          required property int index
          readonly property var item: root.items[entry.index] ?? {
            "uid": "",
            "summary": "",
            "done": false
          }
          readonly property bool renaming: root.editing !== "" && root.editing === entry.item.uid

          Layout.fillWidth: true
          spacing: 0

          ItemRow {
            visible: !entry.renaming
            icon: entry.item.done ? "check_box" : "check_box_outline_blank"
            marked: entry.item.done || PomodoroManager.todoUid === entry.item.uid
            title: entry.item.summary
            titleLines: 2
            subtitle: PomodoroManager.todoUid === entry.item.uid && !entry.item.done ? I18n.tr("Working on it") : ""
            opacity: entry.item.done ? 0.55 : 1
            onActivated: TodoManager.toggle(entry.item.uid)

            FlatIconButton {
              size: Math.round(Appearance.fontSize * 1.8)
              iconText: "edit"
              tooltipText: I18n.tr("Rename")
              onClicked: {
                root.editing = entry.item.uid;
                renameField.text = entry.item.summary;
                renameField.input.forceActiveFocus();
                renameField.input.selectAll();
              }
            }
            FlatIconButton {
              visible: root.showFocus && !entry.item.done
              size: Math.round(Appearance.fontSize * 1.8)
              iconText: "timer"
              tooltipText: I18n.tr("Work on this")
              onClicked: {
                PomodoroManager.setTodo(entry.item.uid);
                if (!PomodoroManager.running)
                  PomodoroManager.start();
              }
            }
            FlatIconButton {
              size: Math.round(Appearance.fontSize * 1.8)
              iconText: "delete"
              tooltipText: I18n.tr("Delete")
              onClicked: TodoManager.remove(entry.item.uid)
            }
          }

          StyledTextEntry {
            id: renameField
            visible: entry.renaming
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height
            onAccepted: root.rename(entry.item.uid, renameField.text)
            input.onActiveFocusChanged: {
              if (!renameField.input.activeFocus && entry.renaming)
                root.rename(entry.item.uid, renameField.text);
            }
          }
        }
      }
    }
  }

  // A plain Item takes the free height in a card
  Item {
    visible: root.items.length === 0
    Layout.fillWidth: true
    Layout.fillHeight: root.fill
    Layout.preferredHeight: root.fill ? -1 : empty.implicitHeight + Widget.spacing * 2

    EmptyState {
      id: empty
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: root.fill ? parent.height : -1
      icon: "task_alt"
      text: TodoManager.items.length > 0 ? I18n.tr("All done") : I18n.tr("Nothing to do")
    }
  }
}
