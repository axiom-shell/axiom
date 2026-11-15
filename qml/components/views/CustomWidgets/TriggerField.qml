pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// What one trigger runs (an element's On press, the bar's Click…): a row
// with the dropdown of the widget's actions (Nothing, each one, New action…)
// laid out as the settings page lays one out (InspectorRow's `shortControl`:
// under its label in a narrow form, beside it in a wide one; a click on the
// row opens it), under it what the pick runs (its command as it would be
// filled from the previewed sample, with the argument, or the Axiom action's
// name) and an Edit button that opens the action's ActionRow under the
// field; then, for a command action, the trigger's Argument (words added to
// the command: CustomWidgetData.commandLine) as a row of its own on the rail
// under it, as a part's field under its selector. "New action…" makes an action named
// `newName`, picks it and opens it. A ref that names no action (it was
// removed) says so. `writeRun(value)` writes the pick: the element's
// `run.<trigger>` or the bar's `bar.run.<trigger>`; `writeArg(text)` the
// argument (`args.<trigger>`, `bar.args.<trigger>`).
ColumnLayout {
  id: root

  // The trigger's title, and the top row of its box
  property string label: ""
  property bool first: false
  readonly property var editor: CustomWidgetsManager.editor
  // The action picked (its id; "" nothing)
  property string current: ""
  property var writeRun: value => {}
  // The trigger's argument
  property string arg: ""
  property var writeArg: value => {}
  // Whether the trigger has a value of its own ({value}); a Button's click
  // and the bar's clicks have none: their {value} is the argument
  property bool ownValue: true
  // The name "New action…" gives the action
  property string newName: ""
  // What {value} is filled with in the caption (the element's value)
  property string valueText: ""

  readonly property var items: root.editor.selected?.actions?.items ?? []
  readonly property int actionIndex: root.current === "" ? -1 : root.items.findIndex(a => a.id === root.current)
  readonly property var action: root.items[root.actionIndex] ?? null
  readonly property bool removed: root.current !== "" && root.action === null
  readonly property bool editing: root.action !== null && root.editor.editingAction === root.action.id
  // What it runs, as the previewed sample fills it
  readonly property string runs: {
    if (root.action === null)
      return "";
    if (root.action.kind === "axiom")
      return root.editor.axiomChoices.find(c => c.value === root.action.axiom)?.label ?? root.action.axiom;
    return CustomWidgetData.commandLine(root.action.command, root.arg, {
      "value": root.ownValue ? root.valueText : undefined,
      "ownValue": root.ownValue,
      "rev": CustomWidgetData.asText(root.editor.previewFields?.rev),
      "tree": Paths.treePath,
      "fields": root.editor.previewFields
    });
  }

  Layout.fillWidth: true
  spacing: 0

  InspectorRow {
    first: root.first
    label: root.label
    shortControl: true
    dropdown: combo
    belowShown: root.action !== null || root.removed

    StyledComboEntry {
      id: combo
      Layout.fillWidth: true
      value: root.current
      options: root.editor.actionChoices
      onPicked: value => {
        if (value === "__new")
          root.editor.newActionFor(root.newName, root.writeRun);
        else
          root.writeRun(value);
      }
    }

    below: [
      RowLayout {
        visible: root.action !== null
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          Layout.fillWidth: true
          text: root.runs === "" ? I18n.tr("No command yet") : root.action?.kind === "axiom" ? root.runs : I18n.tr("Runs: {0}", root.runs)
          textFamily: root.action?.kind === "axiom" || root.runs === "" ? Appearance.fontFamily : "monospace"
          role: "caption"
          tone: root.runs === "" ? "warning" : "muted"
          elide: Text.ElideMiddle // style-exempt: middle
        }
        StyledTextButton {
          implicitHeight: Widget.smallHeight
          kind: "text"
          text: root.editing ? I18n.tr("Done") : I18n.tr("Edit")
          onClicked: root.editor.editingAction = root.editing ? "" : root.action.id
        }
      },
      StyledText {
        visible: root.removed
        Layout.fillWidth: true
        text: I18n.tr("This action was removed")
        role: "caption"
        tone: "warning"
      },
      Loader {
        active: root.editing
        visible: active
        Layout.fillWidth: true
        Layout.topMargin: Widget.spacing / 2

        sourceComponent: ActionRow {
          openAtStart: true
          index: root.actionIndex
        }
      }
    ]
  }

  // Axiom actions ignore it (the text is kept)
  InspectorRow {
    indented: true
    shown: root.action?.kind === "command"
    label: I18n.tr("Argument")
    description: I18n.tr("Added to the end of the command, or where it says {arg}. Words are quoted for you: it can't run anything.")

    StyledTextEntry {
      id: argEntry
      Layout.fillWidth: true
      placeholderText: I18n.tr("e.g. next")
      input.font.family: "monospace"
      onTextEdited: root.writeArg(argEntry.text)

      Binding {
        target: argEntry
        property: "text"
        value: root.arg
        when: !argEntry.input.activeFocus
        restoreMode: Binding.RestoreNone
      }
    }
  }
}
