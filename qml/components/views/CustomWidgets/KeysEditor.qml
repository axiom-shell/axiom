pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page: the selected definition's `module.keys` as rows, each
// a key (captured by pressing it) and the action it runs, with Remove and an
// add button. They work in the overlay, edge menus and the bar popout, once
// the module is clicked (at once in the popout); not while an Entry has the
// focus. Rows are by count over the saved keys.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var keys: root.editor.selected?.module?.keys ?? ({})
  readonly property var names: Object.keys(root.keys)

  Layout.fillWidth: true
  spacing: Widget.spacing

  Repeater {
    model: root.names.length

    RowLayout {
      id: row
      required property int index
      readonly property string key: root.names[row.index] ?? ""
      Layout.fillWidth: true
      spacing: Widget.spacing

      KeyCapture {
        value: row.key
        onCaptured: name => root.editor.set(["module", "keys"], CustomWidgetData.renameKey(root.keys, row.key, name))
      }
      StyledComboEntry {
        Layout.fillWidth: true
        editable: true
        placeholderText: I18n.tr("An action")
        value: root.keys[row.key] ?? ""
        options: root.editor.actionOptions.slice(1)
        onPicked: value => root.editor.set(["module", "keys"], CustomWidgetData.withKey(root.keys, row.key, value))
      }
      SquareIconButton {
        iconText: "close"
        tooltipText: I18n.tr("Remove this key")
        onClicked: root.editor.set(["module", "keys"], CustomWidgetData.withoutKey(root.keys, row.key))
      }
    }
  }

  StyledTextButton {
    implicitHeight: Widget.height
    iconText: "add"
    text: I18n.tr("Add a key")
    // A new row: a free digit, which a press replaces, running the first
    // built-in until another is picked
    onClicked: root.editor.set(["module", "keys"], CustomWidgetData.withKey(root.keys, ["1", "2", "3", "4", "5", "6", "7", "8", "9"].find(k => !(k in root.keys)) ?? Utils.freeId("1", root.names), root.editor.actionOptions[1].value))
  }
}
