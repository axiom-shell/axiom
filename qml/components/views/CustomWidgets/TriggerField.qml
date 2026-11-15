pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// What one trigger runs (an element's On press, the bar's Click…): a
// dropdown of the widget's actions (Nothing, each one, New action…), under
// it what the pick runs (its command as it would be filled from the previewed
// sample, or the Axiom action's name) and an Edit button that opens the
// action's ActionRow under the field. "New action…" makes an action named
// `newName`, picks it and opens it. A ref that names no action (it was
// removed) says so. `writeRun(value)` writes the pick: the element's
// `run.<trigger>` or the bar's `bar.run.<trigger>`.
InspectorRow {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  // The action picked (its id; "" nothing)
  property string current: ""
  property var writeRun: value => {}
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
    return CustomWidgetData.fillCommand(root.action.command, {
      "value": root.valueText,
      "rev": CustomWidgetData.asText(root.editor.previewFields?.rev),
      "tree": Paths.treePath
    });
  }

  StyledComboEntry {
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
