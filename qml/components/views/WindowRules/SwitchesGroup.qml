pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Window rules page, left: the built-in switches (Float Steam's small
// windows, Send games to a special workspace), each with Copy as rule, which
// turns it into a rule to edit; the games switch's problems show under it.
FieldGroup {
  id: root

  readonly property var editor: WindowRulesManager.editor
  readonly property var schema: ConfigManager.configSchema.properties.WindowRules.properties.switches
  readonly property var gamesSchema: root.schema.properties.gamesSpecial
  readonly property var problems: WindowRuleIssues.of(root.editor.report, "").map(issue => ({
        "level": "error",
        "text": root.editor.issueText(issue)
      }))

  function copyAction(key) {
    return {
      "text": I18n.tr("Copy as rule"),
      "icon": "content_copy",
      "run": () => root.editor.copySwitch(key)
    };
  }

  title: I18n.tr(root.schema.title)
  description: I18n.tr(root.schema.description)

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: Utils.pick(root.schema.properties, ["steamFloat"])
    order: ["steamFloat"]
    values: root.editor.switches
    onEdited: (path, value) => root.editor.setSwitch(path, value)
    fieldAction: path => path[0] === "steamFloat" ? root.copyAction("steamFloat") : null
  }

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: root.gamesSchema.properties
    order: ["enabled", "special"]
    values: root.editor.switches.gamesSpecial ?? ({})
    onEdited: (path, value) => root.editor.setSwitch(["gamesSpecial"].concat(path), value)
    fieldAction: path => path[0] === "enabled" && CompositorManager.supports.namedSpecial ? root.copyAction("gamesSpecial") : null
  }

  IssueList {
    issues: root.problems
  }
}
