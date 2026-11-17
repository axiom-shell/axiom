pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.forms

// A CustomShowWhen condition as form rows ({test, key, value}): one row, its
// label with the Always | When toggle beside it (SchemaToggle, a click on the
// row off the toggle flipping it), then, while it is When, on the rail under
// it as a part's fields under its switch: the key, the test and, for is /
// is not / above / below, the value. Visible and Enabled use it. Page-local:
// only this page reads CustomShowWhen. `write(field, value)` stores one field
// (`test`, `key` or `value`) of the condition
FormColumn {
  id: root

  joins: true

  // The row's label, and what it does
  property string label: ""
  property string description: ""
  // The condition: {test, key, value}
  property var value: ({})
  // The keys the key field offers
  property var keys: []
  // The tests the dropdown offers, [{value, label}] (`always` has no entry:
  // the toggle is its place)
  property var tests: []
  // The test the toggle's When picks
  property string whenTest: "is"
  property var write: function (field, value) {}

  readonly property string test: root.value?.test ?? "always"
  readonly property bool on: root.test !== "always"
  readonly property bool needsValue: ["is", "isNot", "above", "below"].includes(root.test)

  Layout.fillWidth: true
  spacing: 0

  FormRow {
    activates: toggle
    bodyHeight: toggle.implicitHeight

    SchemaToggle {
      id: toggle
      width: parent.width
      label: root.label
      description: root.description
      options: ["always", "when"]
      optionLabels: ({
          "always": I18n.tr("Always"),
          "when": I18n.tr("When")
        })
      currentValue: root.on ? "when" : "always"
      onPicked: value => root.write("test", value === "always" ? "always" : root.whenTest)
    }
  }

  FieldRow {
    level: 1
    shown: root.on
    label: I18n.tr("Key")
    description: I18n.tr("Empty: what the element shows.")
    shortControl: true
    activates: keyField

    KeyField {
      id: keyField
      Layout.fillWidth: true
      keys: root.keys
      value: root.value?.key ?? ""
      onPicked: value => root.write("key", value)
    }
  }

  FormRow {
    level: 1
    shown: root.on
    activates: testField
    bodyHeight: testField.implicitHeight

    SchemaComboBox {
      id: testField
      width: parent.width
      label: I18n.tr("Test")
      options: root.tests.map(t => t.value)
      optionLabels: root.tests.reduce((labels, t) => {
        labels[t.value] = t.label;
        return labels;
      }, {})
      currentValue: root.test
      onSelectionChanged: value => root.write("test", value)
    }
  }

  FieldRow {
    level: 1
    shown: root.on && root.needsValue
    label: I18n.tr("Value")

    CommitEntry {
      Layout.fillWidth: true
      live: true
      value: root.value?.value ?? ""
      onEdited: text => root.write("value", text)
    }
  }
}
