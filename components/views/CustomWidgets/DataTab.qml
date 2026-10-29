pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page, Data tab: the script's last output as it came, and
// every value in it with its path (what the module's elements bind to).
// Each field reads the output's key of the same name: the script shapes
// its own JSON.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property string widgetId: root.editor.selectedId
  readonly property var output: CustomWidgetsManager.outputs[root.widgetId] ?? null
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var sample: root.fields?.sample ?? null
  readonly property var paths: root.sample ? CustomWidgetData.flatten(root.sample) : []
  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  function shown(value) {
    if (value === undefined || value === null)
      return "";
    return typeof value === "object" ? JSON.stringify(value) : String(value);
  }

  // Run state, and Run now
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: !root.definition?.command ? I18n.tr("No command") : root.output === null ? I18n.tr("Waiting") : root.output.blocked ? I18n.tr("Not run") : root.output.error ? I18n.tr("Failed") : I18n.tr("Running")
      color: !root.definition?.command || root.output?.blocked ? Theme.foregroundAlt : root.output?.error ? Theme.error : root.output === null ? Theme.warning : Theme.success
    }
    StyledText {
      Layout.fillWidth: true
      text: root.output?.error ? root.output.error : root.output?.at ? I18n.tr("Last output {0}", I18n.formatDate(new Date(root.output.at), I18n.dateFormat("dateTime"))) : ""
      elide: Text.ElideRight
      opacity: 0.7
    }
    StyledTextButton {
      implicitHeight: Widget.height
      enabled: !!root.definition?.command
      iconText: "play_arrow"
      text: I18n.tr("Run now")
      onClicked: CustomWidgetsManager.refresh(root.widgetId)
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Output")
    description: I18n.tr("The last thing the script printed, as it came.")

    StyledText {
      Layout.fillWidth: true
      text: root.output?.text ? root.output.text.slice(0, 4000) : I18n.tr("Nothing yet")
      textFamily: "monospace"
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 12
      elide: Text.ElideRight
      opacity: root.output?.text ? 1 : 0.6
    }
  }

  FieldGroup {
    visible: root.paths.length > 0
    Layout.fillWidth: true
    title: I18n.tr("What's in it")
    description: I18n.tr("Each value the output holds, by its path: the module's elements show them. The bar reads Waybar's keys (text, alt, tooltip, class, percentage) and axiom's (icon, value, min, max, unit, subtext, state, badge, urgent, image, items, hidden).")

    // By count: a new sample of the same shape rebuilds nothing
    Repeater {
      model: root.paths.length

      RowLayout {
        id: pathRow
        required property int index
        readonly property var entry: root.paths[index] ?? ({})
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 12
          text: pathRow.entry.path ?? ""
          textFamily: "monospace"
          textSize: Appearance.fontSizeBy(-1)
          elide: Text.ElideMiddle
        }
        StyledText {
          Layout.fillWidth: true
          text: pathRow.entry.type === "array" ? I18n.tr("a list of {0}", pathRow.entry.value) : pathRow.entry.type === "object" ? "{…}" : root.shown(pathRow.entry.value)
          elide: Text.ElideRight
          opacity: 0.7
        }
      }
    }
  }
}
