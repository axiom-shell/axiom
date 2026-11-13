pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// One kind of window in a rule (RuleInspector): its conditions, each a row
// (what to test, how, against what), Add a condition, and the kind's own
// problems and notes. Every condition is read by index from the draft.
StyledContainer {
  id: root

  // The kind's place in the rule's windows
  required property int k

  readonly property var editor: WindowRulesManager.editor
  readonly property var kind: root.editor.selected?.windows?.[root.k] ?? ({})
  readonly property var issues: WindowRuleIssues.of(root.editor.report, root.editor.selectedId)
  readonly property var row: WindowRuleIssues.rowOf(root.editor.report, root.editor.selectedId)
  readonly property var notes: {
    const list = WindowRuleIssues.atKind(root.issues, root.k).map(issue => ({
          "level": "error",
          "text": root.editor.issueText(issue)
        }));
    if ((root.row?.skipped ?? []).includes(root.k))
      list.push({
        "level": "warning",
        "text": I18n.tr("{0} can't match this kind, so it isn't written.", CompositorManager.displayName)
      });
    if ((root.row?.live ?? []).includes(root.k))
      list.push({
        "level": "info",
        "text": I18n.tr("axiom matches this kind just after the window opens, so the window may jump briefly.")
      });
    return list;
  }

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight + Widget.padding * 2
  backgroundColor: Qt.alpha(Theme.backgroundHighlight, 0.4)

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    RowLayout {
      Layout.fillWidth: true

      StyledLabel {
        Layout.fillWidth: true
        text: I18n.tr("Kind {0}", root.k + 1)
        font.bold: true
      }

      StyledIconButton {
        iconText: "close"
        tooltipText: I18n.tr("Remove this kind")
        hoverColor: Theme.error
        onClicked: root.editor.removeKind(root.k)
      }
    }

    Repeater {
      model: root.kind.conditions?.length ?? 0

      delegate: ConditionRow {
        required property int index
        Layout.fillWidth: true
        c: index
      }
    }

    StyledTextButton {
      implicitHeight: Widget.height
      iconText: "add"
      text: I18n.tr("Add a condition")
      onClicked: root.editor.addCondition(root.k)
    }

    IssueList {
      issues: root.notes
    }
  }

  // A condition: the window's field, the test, its value, remove; its own
  // problems under it
  component ConditionRow: ColumnLayout {
    id: cond

    required property int c
    readonly property var condition: root.kind.conditions?.[cond.c] ?? ({})
    readonly property var schema: ConfigManager.configSchema.definitions.WindowRuleCondition.properties
    readonly property var issues: WindowRuleIssues.atCondition(root.issues, root.k, cond.c).map(issue => ({
          "level": "error",
          "text": root.editor.issueText(issue)
        }))
    readonly property bool valueShown: SchemaLayout.showIfHolds(cond.schema.value["x-showIf"], key => cond.condition[key])

    // The enum's options (one the condition holds stays), labelled from
    // the schema
    function options(prop, allowed) {
      const labels = cond.schema[prop]["x-enumLabels"] ?? ({});
      const current = cond.condition[prop];
      return Array.prototype.slice.call(cond.schema[prop].enum).filter(value => allowed(value) || value === current).map(value => ({
            "value": value,
            "label": I18n.tr(labels[value] ?? value)
          }));
    }

    spacing: Widget.spacing / 2

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledComboEntry {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: Widget.px(150)
        value: cond.condition.field ?? "appId"
        options: cond.options("field", field => root.editor.offeredFields.includes(field) && SchemaLayout.showIfHolds(cond.schema.field["x-enumShowIf"]?.[field], key => CompositorManager.supports[key.slice("/$supports.".length)]))
        onPicked: value => root.editor.setCondition(root.k, cond.c, "field", value)
      }

      StyledComboEntry {
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: Widget.px(110)
        value: cond.condition.op ?? "is"
        options: cond.options("op", op => SchemaLayout.showIfHolds(cond.schema.op["x-enumShowIf"]?.[op], key => cond.condition[key]))
        onPicked: value => root.editor.setCondition(root.k, cond.c, "op", value)
      }

      StyledTextEntry {
        id: valueText
        visible: cond.valueShown
        Layout.alignment: Qt.AlignTop
        Layout.fillWidth: true
        Layout.preferredWidth: Widget.px(150)
        readonly property string saved: cond.condition.value ?? ""
        placeholderText: cond.condition.field === "steamGame" ? I18n.tr("A number, such as 570") : cond.condition.op === "matches" ? I18n.tr("A pattern") : ""

        Component.onCompleted: valueText.input.text = valueText.saved
        // Released, not committed: a removal has shifted the indexes by the
        // time this goes (the editor commits first)
        Component.onDestruction: EditsManager.releaseTyping(valueText)
        onSavedChanged: {
          if (!valueText.typed)
            valueText.input.text = valueText.saved;
        }
        onTextEdited: EditsManager.holdTyping(valueText, valueText.Window.window)
        input.onEditingFinished: valueText.commitTyped()

        function commitTyped() {
          if (valueText.typed)
            root.editor.setCondition(root.k, cond.c, "value", valueText.input.text);
          valueText.typed = false;
          EditsManager.releaseTyping(valueText);
        }

        function discardTyped() {
          valueText.typed = false;
          valueText.input.text = valueText.saved;
          EditsManager.releaseTyping(valueText);
        }
      }

      StyledIconButton {
        Layout.alignment: Qt.AlignTop
        iconText: "close"
        tooltipText: I18n.tr("Remove this condition")
        hoverColor: Theme.error
        onClicked: root.editor.removeCondition(root.k, cond.c)
      }
    }

    IssueList {
      issues: cond.issues
    }
  }
}
