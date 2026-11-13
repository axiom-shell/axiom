pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// Window rules page, right: the selected rule. Its name, icon and switch;
// its kinds of window and their conditions; what happens when one opens
// (greyed where the compositor can't); and the rule's problems. Built anew
// for each selection (a KeyedLoader), so typed text never lands on another
// rule; conditions are read by index.
ColumnLayout {
  id: root

  readonly property var editor: WindowRulesManager.editor
  readonly property var rule: root.editor.selected ?? ({})
  readonly property var schema: ConfigManager.configSchema.definitions.WindowRule.properties
  readonly property var issues: WindowRuleIssues.of(root.editor.report, root.rule.id)
  readonly property var row: WindowRuleIssues.rowOf(root.editor.report, root.rule.id)
  readonly property var general: WindowRuleIssues.general(root.issues)
  // The effects only the daemon places, after the window opens
  readonly property var placedNotes: (root.row?.placed ?? []).map(key => ({
        "level": "info",
        "text": I18n.tr("{0}: applied just after the window opens.", I18n.tr(root.schema.window.properties[key]?.title ?? key))
      }))
  // "Don't focus when it opens" isn't applied to the kinds axiom matches
  // after the window opens
  readonly property var noFocusNotes: root.rule.window?.noFocus === true && (root.row?.live ?? []).length > 0 ? [
    {
      "level": "info",
      "text": I18n.tr("Don't focus when it opens: not applied to the kinds axiom matches just after the window opens.")
    }
  ] : []
  // The open windows the picker lists, taken when it opens
  property var windowTypes: []
  property var appTypes: []
  readonly property var generalNotes: root.general.map(issue => ({
        "level": "error",
        "text": root.editor.issueText(issue)
      }))

  spacing: Widget.spacing * 2

  SchemaPropertiesForm {
    Layout.fillWidth: true
    propertiesSchema: Utils.pick(root.schema, order)
    order: ["name", "icon", "enabled"]
    values: root.rule
    onEdited: (path, value) => root.editor.set(path, value)
  }

  FieldGroup {
    title: I18n.tr(root.schema.windows.title)
    description: I18n.tr(root.schema.windows.description)

    Repeater {
      model: root.rule.windows?.length ?? 0

      delegate: ColumnLayout {
        id: kindItem
        required property int index
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          visible: kindItem.index > 0
          text: I18n.tr("or")
          opacity: 0.6
        }

        KindBlock {
          Layout.fillWidth: true
          k: kindItem.index
        }
      }
    }

    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledTextButton {
        implicitHeight: Widget.height
        iconText: "add"
        text: I18n.tr("Add another kind")
        onClicked: root.editor.addKind()
      }

      StyledTextButton {
        id: fromWindowButton
        visible: WindowRulesManager.state?.running === true
        implicitHeight: Widget.height
        iconText: "select_window"
        text: I18n.tr("Add from open window")
        onClicked: WindowRulesManager.windows(list => {
          root.windowTypes = list.map(w => ({
                "type": w.id,
                "label": w.title || w.appId || w.id,
                "image": AppIconManager.resolveWindowIcon(w.appId, w.title),
                "detail": WindowRulesManager.windowDetail(w),
                "keywords": [w.appId, w.process?.name ?? ""]
              }));
          windowPicker.openAt(fromWindowButton);
        })
      }

      StyledTextButton {
        id: addAppButton
        implicitHeight: Widget.height
        iconText: "apps"
        text: I18n.tr("Add app")
        onClicked: {
          root.appTypes = WindowRulesManager.apps("").map(o => ({
                "type": o.value,
                "label": o.label,
                "image": o.image
              }));
          appPicker.openAt(addAppButton);
        }
      }
    }
  }

  FieldGroup {
    title: I18n.tr(root.schema.window.title)
    description: I18n.tr(root.schema.window.description)

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: root.schema.window.properties
      order: ["float", "size", "center", "workspace", "follow", "special", "monitor", "fullscreen", "maximize", "pin", "opacity", "noBlur", "noFocus", "noScreenShare", "tearing"]
      values: root.rule.window ?? ({})
      onEdited: (path, value) => root.editor.set(["window"].concat(path), value)
    }

    IssueList {
      issues: root.placedNotes.concat(root.noFocusNotes)
    }
  }

  FieldGroup {
    visible: root.generalNotes.length > 0
    title: I18n.tr("Problems")
    description: I18n.tr("A rule with problems is saved but not applied.")

    IssueList {
      issues: root.generalNotes
    }
  }

  // Names and titles aren't translation keys
  TypePickerPopup {
    id: windowPicker
    parent: root
    implicitWidth: Widget.px(420)
    types: root.windowTypes
    labelOf: type => type.label
    placeholderText: I18n.tr("Search open windows")
    onTypeSelected: type => root.editor.addKindFromWindow(type)
  }

  TypePickerPopup {
    id: appPicker
    parent: root
    types: root.appTypes
    labelOf: type => type.label
    placeholderText: I18n.tr("Search apps")
    onTypeSelected: type => root.editor.addApp(type)
  }
}
