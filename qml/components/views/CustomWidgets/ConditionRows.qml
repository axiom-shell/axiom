pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A CustomShowWhen condition as inspector rows ({test, key, value}): the
// Always | When toggle, then (while it is When) the key, the test and, for
// is / is not / above / below, the value. Visible and Enabled use it. Page-local:
// only this page reads CustomShowWhen. `write(field, value)` stores one field
// (`test`, `key` or `value`) of the condition
ColumnLayout {
  id: root

  // The row's caption
  property string label: ""
  // The condition: {test, key, value}
  property var value: ({})
  // The keys the key field offers
  property var keys: []
  // The tests the combo offers (`always` has no entry: the toggle is its place)
  property var tests: []
  // The test the toggle's When picks
  property string whenTest: "is"
  // The top row of its box
  property bool first: false
  property var write: function (field, value) {}

  readonly property string test: root.value?.test ?? "always"
  readonly property bool on: root.test !== "always"
  readonly property bool needsValue: ["is", "isNot", "above", "below"].includes(root.test)

  Layout.fillWidth: true
  spacing: 0

  InspectorRow {
    first: root.first
    label: root.label

    StyledToggle {
      Layout.fillWidth: true
      options: ["always", "when"]
      labels: ({
          "always": I18n.tr("Always"),
          "when": I18n.tr("When")
        })
      value: root.on ? "when" : "always"
      onPicked: value => root.write("test", value === "always" ? "always" : root.whenTest)
    }
  }

  InspectorRow {
    indented: true
    shown: root.on

    KeyField {
      Layout.fillWidth: true
      keys: root.keys
      value: root.value?.key ?? ""
      onPicked: value => root.write("key", value)
    }
  }

  InspectorRow {
    indented: true
    shown: root.on

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledComboEntry {
        Layout.preferredWidth: Widget.px(120)
        Layout.fillWidth: !root.needsValue
        value: root.test
        options: root.tests
        onPicked: value => root.write("test", value)
      }

      StyledTextEntry {
        id: whenValue
        visible: root.needsValue
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        placeholderText: I18n.tr("Value")
        onTextEdited: root.write("value", whenValue.text)
        Binding {
          target: whenValue
          property: "text"
          value: root.value?.value ?? ""
          when: !whenValue.input.activeFocus
          restoreMode: Binding.RestoreNone
        }
      }
    }
  }
}
