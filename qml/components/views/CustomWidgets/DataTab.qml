pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.views.base

// Custom widgets page, Data tab: the script's last output as it came (with
// its exit code and last stderr line when it failed), and
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
  // The screens' samples kept in the definition: their keys
  readonly property var sampleKeys: Object.keys(root.definition?.samples ?? ({}))
  // The edited layer's name, for the Keep button
  readonly property string layerName: root.editor.sampleKey === "" ? I18n.tr("no screen") : (root.definition?.module.views[root.editor.viewIndex]?.name || root.editor.sampleKey)
  readonly property string keepReason: root.editor.keepRefused === "count" ? I18n.tr("{0} samples are kept: remove one first", root.editor.sampleLimits.entries) : root.editor.keepRefused === "size" ? I18n.tr("The samples are over {0} KB: remove one first", root.editor.sampleLimits.bytes / 1024) : ""
  // Rows built at most: a large output lists its first paths
  readonly property int maxRows: 200
  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  // Run state, and Run now
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      text: !root.definition?.command ? I18n.tr("No command") : root.output === null ? I18n.tr("Waiting") : root.output.blocked ? I18n.tr("Not run") : root.output.error ? I18n.tr("Failed") : I18n.tr("Running")
      tone: !root.definition?.command || root.output?.blocked ? "neutral" : root.output?.error ? "error" : root.output === null ? "warning" : "success"
    }
    StyledLabel {
      Layout.fillWidth: true
      text: root.output?.error ? root.output.error : root.output?.at ? I18n.tr("Last output {0}", I18n.formatDate(new Date(root.output.at), I18n.dateTimeFormat())) : ""
      tone: "muted"
    }
    StyledTextButton {
      implicitHeight: Widget.height
      enabled: !!root.definition?.command
      iconText: "play_arrow"
      text: I18n.tr("Run now")
      onClicked: CustomWidgetsManager.refresh(root.widgetId)
    }
  }

  // The groups flow into columns, as a Settings card's rows do
  GroupColumns {
    Layout.fillWidth: true

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Samples")
      description: I18n.tr("A sample per screen is saved in the config with the definition: the Module tab previews each screen with it before the script reaches it.")

      StyledTextButton {
        implicitHeight: Widget.height
        enabled: root.editor.liveSample !== null && root.keepReason === ""
        iconText: "bookmark_add"
        text: I18n.tr("Keep as the sample of {0}", root.layerName)
        tooltipText: root.keepReason
        onClicked: root.editor.keepSample()
      }
      StyledText {
        visible: root.keepReason !== ""
        Layout.fillWidth: true
        text: root.keepReason
        tone: "warning"
        overflow: "wrap"
      }

      // By count, over the kept keys (config, never live values)
      Repeater {
        model: root.sampleKeys.length

        RowLayout {
          id: sampleRow
          required property int index
          readonly property string key: root.sampleKeys[sampleRow.index] ?? ""
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            Layout.fillWidth: true
            text: sampleRow.key === "" ? I18n.tr("No screen") : (root.definition?.module.views.find(v => v.id === sampleRow.key)?.name || sampleRow.key)
            overflow: "line"
          }
          SquareIconButton {
            iconText: "close"
            tooltipText: I18n.tr("Forget this sample")
            onClicked: root.editor.removeSample(sampleRow.key)
          }
        }
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
        role: "caption"
        tone: root.output?.text ? "" : "faint"
        overflow: "wrap"
        maxLines: 12
      }
      StyledLabel {
        visible: root.output !== null && !root.output.blocked && root.output.exitCode > 0
        Layout.fillWidth: true
        text: I18n.tr("Exit code {0}", root.output?.exitCode ?? 0)
        tone: "muted"
      }
      StyledText {
        visible: !!root.output?.stderr
        Layout.fillWidth: true
        text: root.output?.stderr ?? ""
        textFamily: "monospace"
        role: "caption"
        tone: "muted"
        overflow: "wrap"
        maxLines: 3
      }
    }

    FieldGroup {
      visible: root.paths.length > 0
      Layout.fillWidth: true
      title: I18n.tr("What's in it")
      description: I18n.tr("Each value the output holds, by its path: the module's elements show them. The bar reads Waybar's keys (text, alt, tooltip, class, percentage) and axiom's (icon, value, min, max, unit, subtext, state, badge, urgent, image, items, hidden).")

      // By count: a new sample of the same shape rebuilds nothing
      Repeater {
        model: Math.min(root.paths.length, root.maxRows)

        RowLayout {
          id: pathRow
          required property int index
          readonly property var entry: root.paths[index] ?? ({})
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            Layout.preferredWidth: Appearance.fontSize * 12
            text: pathRow.entry.path ?? ""
            textFamily: "monospace"
            role: "caption"
            elide: Text.ElideMiddle // style-exempt: middle
          }
          StyledLabel {
            Layout.fillWidth: true
            text: pathRow.entry.type === "array" ? I18n.tr("a list of {0}", pathRow.entry.value) : pathRow.entry.type === "object" ? "{…}" : CustomWidgetData.asText(pathRow.entry.value)
            tone: "muted"
          }
        }
      }

      StyledText {
        visible: root.paths.length > root.maxRows
        text: I18n.tr("…and {0} more", root.paths.length - root.maxRows)
        tone: "muted"
      }
    }
  }
}
