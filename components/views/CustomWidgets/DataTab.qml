pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page, Data tab: the script's last output as it came, the
// paths in it (each can become a field), and every field with where it
// reads from and what it reads now. Paths are offered from the live
// sample; the field list is fixed (CustomWidgetData.fieldNames).
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property string widgetId: root.editor.selectedId
  readonly property var output: CustomWidgetsManager.outputs[root.widgetId] ?? null
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var sample: root.fields?.sample ?? null
  readonly property var paths: root.sample ? CustomWidgetData.flatten(root.sample) : []
  // The binding choices: the sample's leaves (an array too, for items)
  readonly property var pathOptions: [
    {
      "value": "",
      "label": I18n.tr("Its own key")
    }
  ].concat(root.paths.filter(p => p.type !== "object").map(p => ({
        "value": p.path,
        "label": p.path
      })))

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
    description: I18n.tr("Each value the output holds. Pick a field to show it as.")

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
        StyledComboEntry {
          visible: pathRow.entry.type !== "object"
          Layout.preferredWidth: Appearance.fontSize * 10
          value: ""
          placeholderText: I18n.tr("Show as…")
          options: CustomWidgetData.fieldNames.map(name => ({
                "value": name,
                "label": name
              }))
          onPicked: name => root.editor.set(["fields", name], pathRow.entry.path)
        }
      }
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Fields")
    description: I18n.tr("Where each field reads from: its own key in the output, a path in it, or a format such as {data.temp}°.")

    Repeater {
      model: CustomWidgetData.fieldNames

      RowLayout {
        id: fieldRow
        required property string modelData
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 6
          text: fieldRow.modelData
          font.bold: true
        }
        StyledComboEntry {
          Layout.preferredWidth: Appearance.fontSize * 14
          editable: true
          value: root.definition?.fields?.[fieldRow.modelData] ?? ""
          options: root.pathOptions
          onPicked: value => root.editor.set(["fields", fieldRow.modelData], value)
        }
        StyledText {
          Layout.fillWidth: true
          text: root.shown(CustomWidgetData.bound(root.sample ?? ({}), fieldRow.modelData, root.definition?.fields?.[fieldRow.modelData] ?? ""))
          elide: Text.ElideRight
          opacity: 0.7
        }
      }
    }
  }
}
