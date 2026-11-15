pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Custom widgets page: the selected definition's `states` as rows, each a
// word the script prints (a state or a class) and the theme colour it
// stands for, with Remove, and an add button whose menu offers the states
// seen live (at most 8, CustomWidgetsEditor.seenStates) that have no
// colour yet, and a blank one. The row's name is read once as it is built.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var stateColors: root.editor.selected?.states ?? ({})
  readonly property var names: Object.keys(root.stateColors)
  // The seen states with no colour yet, for the add menu
  readonly property var offered: root.editor.seenStates.filter(state => !(state in root.stateColors))
  readonly property var colors: SettingsManager.optionsFor({
    "x-options": "colors"
  })

  Layout.fillWidth: true
  spacing: Widget.spacing

  // By count, over the saved names (config, never live values)
  Repeater {
    model: root.names.length

    RowLayout {
      id: row
      required property int index
      readonly property string name: root.names[row.index] ?? ""
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledTextEntry {
        id: nameEntry
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        placeholderText: I18n.tr("State")
        onTextEdited: root.editor.set(["states"], CustomWidgetData.renameKey(root.stateColors, row.name, nameEntry.text.trim()))
        Component.onCompleted: nameEntry.text = row.name
      }
      SchemaComboBox {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        label: ""
        options: root.colors
        swatches: true
        currentValue: root.stateColors[row.name] ?? ""
        onSelectionChanged: value => root.editor.set(["states"], CustomWidgetData.withKey(root.stateColors, row.name, value))
      }
      SquareIconButton {
        iconText: "close"
        tooltipText: I18n.tr("Remove this state")
        onClicked: root.editor.set(["states"], CustomWidgetData.withoutKey(root.stateColors, row.name))
      }
    }
  }

  StyledTextButton {
    id: add
    implicitHeight: Widget.height
    iconText: "add"
    text: I18n.tr("Add a state")
    onClicked: menu.openAt(add, 0, add.height)
  }

  StyledContextMenu {
    id: menu
    parent: root
    items: root.offered.map(state => ({
          "id": "seen:" + state,
          "icon": "visibility",
          "text": state
        })).concat([
      {
        "id": "blank",
        "icon": "add",
        "text": I18n.tr("A new state")
      }
    ])
    onTriggered: id => {
      const name = id === "blank" ? Utils.freeId("state", root.names, "-") : id.slice(5);
      root.editor.set(["states"], CustomWidgetData.withKey(root.stateColors, name, "accent"));
    }
  }
}
