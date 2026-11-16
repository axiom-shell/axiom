pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.components.methods
import qs.components.forms
import qs.components.reusable

// One kind of window in a rule (RuleInspector): an ItemBox holding its
// conditions, each a row (what to test, how, against what), Add a condition,
// and the kind's own problems and notes. Every condition is read by index
// from the draft.
ItemBox {
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
    if ((root.row?.missing ?? []).includes(root.k))
      list.push({
        "level": "warning",
        "text": I18n.tr("This app isn't installed, so this kind matches nothing.")
      });
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

  title: I18n.tr("Kind {0}", root.k + 1)
  removable: true
  removeTooltip: I18n.tr("Remove this kind")
  onRemove: root.editor.removeKind(root.k)

  Repeater {
    model: root.kind.conditions?.length ?? 0

    delegate: ConditionRow {
      required property int index
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

  // A condition: the window's field, the test, its value, remove; its own
  // problems under it
  component ConditionRow: FormRow {
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

    bodyHeight: condColumn.implicitHeight

    ColumnLayout {
      id: condColumn
      width: parent.width
      spacing: Widget.spacing / 2

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledComboEntry {
          Layout.alignment: Qt.AlignTop
          Layout.fillWidth: true
          Layout.preferredWidth: Widget.px(150)
          value: cond.condition.field ?? "appId"
          options: cond.options("field", field => SchemaLayout.showIfHolds(cond.schema.field["x-enumShowIf"]?.[field], key => CompositorManager.supports[key.slice("/$supports.".length)]))
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

        // An installed app: picked by name, its desktop file the value
        StyledComboEntry {
          visible: cond.valueShown && cond.condition.field === "app"
          Layout.alignment: Qt.AlignTop
          Layout.fillWidth: true
          Layout.preferredWidth: Widget.px(150)
          editable: true
          placeholderText: I18n.tr("Pick an app")
          search: query => WindowRulesManager.apps(query)
          options: cond.condition.value ? [WindowRulesManager.appOption(cond.condition.value)] : []
          value: cond.condition.value ?? ""
          onPicked: value => root.editor.setCondition(root.k, cond.c, "value", value)
        }

        // Released, not committed, when torn down: a removal has shifted the
        // indexes by then (the editor commits first)
        CommitEntry {
          id: valueText
          visible: cond.valueShown && cond.condition.field !== "app"
          Layout.alignment: Qt.AlignTop
          Layout.fillWidth: true
          Layout.preferredWidth: Widget.px(150)
          value: cond.condition.value ?? ""
          commitOnDestroy: false
          placeholderText: cond.condition.op === "matches" ? I18n.tr("A pattern") : ({
              "steamGame": I18n.tr("A number, such as 570"),
              "process": I18n.tr("A process name, such as steam"),
              "startedFrom": I18n.tr("A program, such as lutris")
            })[cond.condition.field] ?? ""
          onCommitted: text => root.editor.setCondition(root.k, cond.c, "value", text)
        }

        StyledIconButton {
          Layout.alignment: Qt.AlignTop
          iconText: "close"
          tooltipText: I18n.tr("Remove this condition")
          kind: "danger"
          onClicked: root.editor.removeCondition(root.k, cond.c)
        }
      }

      IssueList {
        issues: cond.issues
      }
    }
  }
}
