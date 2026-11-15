pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.views.base

// Custom widgets page, Data tab: the run state, the script (what runs and
// how: name, icon, command, run mode, output, and folded the conditions and
// the head of the script), the widget's actions (ActionsEditor), the
// script's last output as it came (with its exit code and last stderr line
// when it failed), every value in it with its path (what the module's
// elements bind to), the samples and the actions run.
// Each field reads the output's key of the same name: the script shapes
// its own JSON.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var schema: ConfigManager.configSchema.definitions.CustomWidget.properties
  readonly property string widgetId: root.editor.selectedId
  readonly property var output: CustomWidgetsManager.outputs[root.widgetId] ?? null
  readonly property var fields: CustomWidgetsManager.fields[root.widgetId] ?? null
  readonly property var sample: root.fields?.sample ?? null
  readonly property var paths: root.sample ? CustomWidgetData.flatten(root.sample) : []
  // The screens' samples kept in the definition: their keys
  readonly property var sampleKeys: Object.keys(root.definition?.samples ?? ({}))
  // The edited layer's name, for the sample editor button
  readonly property string layerName: root.editor.sampleKey === "" ? I18n.tr("Base") : (root.definition?.module.views[root.editor.viewIndex]?.name || root.editor.sampleKey)
  // The sample editor is open, and why its last Save was refused
  property bool editingSample: false
  property string sampleError: ""
  // Rows built at most: a large output lists its first paths
  readonly property int maxRows: 200
  readonly property string scriptPath: root.editor.scriptPath(root.definition?.command)
  // The script, read (its first 256 KiB, off the UI thread) when its path
  // changes: only a script, text starting with #!, not a program the
  // command names (an ELF)
  property string scriptText: ""
  // Its first lines
  readonly property string scriptHead: root.scriptText.split("\n").slice(0, 40).join("\n")
  // The script refreshes Waybar by signal (pkill -RTMIN+N waybar), which
  // reaches nothing here
  readonly property bool signalsWaybar: /RTMIN/.test(root.scriptText)
  // The refresh name the script can call
  readonly property string refreshTarget: root.definition?.refreshName || root.definition?.id || ""
  property bool advancedOpen: false
  onScriptPathChanged: root._readScript()
  Component.onCompleted: root._readScript()

  function _readScript() {
    const path = root.scriptPath;
    root.scriptText = "";
    if (path !== "")
      CommandManager.run(["head", "-c", "262144", "--", path], (code, out) => {
        // The reply can come after the tab is gone (root then is null)
        if (root && path === root.scriptPath)
          root.scriptText = code === 0 && out.startsWith("#!") ? out : "";
      });
  }

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  // Run state, and Run now
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StatusChip {
      Layout.alignment: Qt.AlignVCenter
      text: !root.definition?.command ? I18n.tr("No command") : root.output === null ? I18n.tr("Waiting") : root.output.blocked ? I18n.tr("Not run") : root.output.error ? I18n.tr("Failed") : I18n.tr("Running")
      tone: !root.definition?.command || root.output?.blocked ? "neutral" : root.output?.error ? "error" : root.output === null ? "warning" : "success"
    }
    StyledLabel {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      text: root.output?.error ? root.output.error : root.output?.at ? I18n.tr("Last output {0}", I18n.formatDate(new Date(root.output.at), I18n.dateTimeFormat())) : ""
      tone: "muted"
    }
    StyledTextButton {
      Layout.alignment: Qt.AlignVCenter
      implicitHeight: Widget.height
      iconText: "help"
      text: I18n.tr("What should my script print?")
      onClicked: root.editor.openHelp("output")
    }
    StyledTextButton {
      Layout.alignment: Qt.AlignVCenter
      implicitHeight: Widget.height
      enabled: !!root.definition?.command
      iconText: "play_arrow"
      text: I18n.tr("Run now")
      onClicked: CustomWidgetsManager.refresh(root.widgetId)
    }
  }

  // The groups flow into columns, as a Settings card's rows do
  GroupColumns {
    rowGap: 0
    Layout.fillWidth: true

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Script")

      // One box of rows: the form's, the command's, the form's again
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: Utils.pick(root.schema, order)
          order: ["name", "icon"]
          values: root.definition ?? ({})
          onEdited: (path, value) => root.editor.set(path, value)
        }

        InspectorRow {
          label: I18n.tr("Command")
          description: I18n.tr(root.schema.command.description)

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledTextEntry {
              id: commandEntry
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              placeholderText: I18n.tr("e.g. ~/bin/cpu.sh")
              input.font.family: "monospace"
              onTextEdited: root.editor.set("command", commandEntry.text)

              Binding {
                target: commandEntry
                property: "text"
                value: root.definition?.command ?? ""
                when: !commandEntry.input.activeFocus
                restoreMode: Binding.RestoreNone
              }
            }
            SquareIconButton {
              Layout.alignment: Qt.AlignVCenter
              iconText: "folder_open"
              tooltipText: I18n.tr("Pick a script…")
              onClicked: FilePickerManager.pick(root, I18n.tr("Pick a script"), {
                "start": root.scriptPath !== "" ? root.scriptPath.replace(/\/[^/]*$/, "") : "~",
                "shortenHome": true
              }, path => root.editor.set("command", path))
            }
          }
        }

        SchemaPropertiesForm {
          Layout.fillWidth: true
          follows: true
          propertiesSchema: Utils.pick(root.schema, order)
          order: ["mode", "interval"]
          values: root.definition ?? ({})
          onEdited: (path, value) => root.editor.set(path, value)
        }

        // Waybar's and axiom's JSON, or the script's text as it is
        FormRow {
          hoverable: true
          bodyHeight: outputField.implicitHeight
          onRowClicked: outputField.activate()

          SchemaToggle {
            id: outputField
            width: parent.width
            label: I18n.tr("Output")
            description: I18n.tr("Auto reads Waybar's or axiom's JSON, else the text.")
            options: ["auto", "text"]
            optionLabels: ({
                "auto": I18n.tr("Auto"),
                "text": I18n.tr("Plain text")
              })
            currentValue: root.definition?.output === "text" ? "text" : "auto"
            onPicked: value => root.editor.set("output", value === "text" ? "text" : "waybar")
          }
        }

        FormRow {
          tinted: false
          bodyHeight: advanced.implicitHeight

          FoldingSection {
            id: advanced
            anchors.left: parent.left
            anchors.right: parent.right
            title: I18n.tr("Advanced")
            collapsed: !root.advancedOpen
            onToggled: root.advancedOpen = !root.advancedOpen

            SchemaPropertiesForm {
              Layout.fillWidth: true
              propertiesSchema: Utils.pick(root.schema, order)
              order: ["execIf", "refreshName"]
              values: root.definition ?? ({})
              onEdited: (path, value) => root.editor.set(path, value)
            }
            StyledText {
              Layout.fillWidth: true
              text: I18n.tr("Run it again from anywhere: {0}", `axiom ipc customWidgets refresh ${root.refreshTarget}`)
              role: "caption"
              tone: "faint"
              overflow: "wrap"
            }
            Surface {
              visible: root.scriptHead !== ""
              Layout.fillWidth: true
              tone: "sunken"
              outlined: true
              implicitHeight: head.implicitHeight + Style.space3 * 2

              ColumnLayout {
                id: head
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space3
                spacing: Widget.spacing / 2

                StyledText {
                  Layout.fillWidth: true
                  text: root.scriptPath
                  role: "caption"
                  tone: "faint"
                  overflow: "wrap"
                }
                StyledText {
                  Layout.fillWidth: true
                  text: root.scriptHead
                  textFamily: "monospace"
                  role: "micro"
                  tone: "muted"
                  // A long line wraps inside the box
                  overflow: "wrap"
                }
              }
            }
          }
        }
      }

      StyledText {
        visible: root.signalsWaybar
        Layout.fillWidth: true
        text: I18n.tr("This script refreshes Waybar with a signal (pkill -RTMIN…), which does nothing here: change it to run {0}.", `axiom ipc customWidgets refresh ${root.refreshTarget}`)
        tone: "warning"
        overflow: "wrap"
      }
    }

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Actions")
      description: I18n.tr("Buttons, list rows, toggles, sliders and the bar's clicks run these.")

      ActionsEditor {}
    }

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Last output")
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

      CustomWidgetPaths {
        Layout.fillWidth: true
        paths: root.paths
        maxRows: root.maxRows
      }
    }

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Samples")
      description: I18n.tr("A sample per screen is saved in the config with the definition: the Module tab previews each screen with it before the script reaches it.")

      // Paste or edit the layer's sample: JSON, checked on Save
      StyledTextButton {
        implicitHeight: Widget.height
        enabled: root.definition !== null
        iconText: root.editingSample ? "expand_less" : "edit_note"
        text: I18n.tr("Paste or edit the sample of {0}", root.layerName)
        onClicked: {
          root.editingSample = !root.editingSample;
          root.sampleError = "";
        }
      }
      Loader {
        active: root.editingSample
        visible: active
        Layout.fillWidth: true

        sourceComponent: ColumnLayout {
          spacing: Widget.spacing / 2

          StyledTextArea {
            id: sampleArea
            Layout.fillWidth: true
            expandable: true
            input.font.family: "monospace"
            placeholderText: I18n.tr("What the script prints, as JSON: {\"text\": \"…\"}")
            Component.onCompleted: sampleArea.text = root.editor.sampleText
          }
          RowLayout {
            Layout.fillWidth: true
            StyledText {
              Layout.fillWidth: true
              text: root.sampleError
              role: "caption"
              tone: "warning"
              overflow: "wrap"
            }
            StyledTextButton {
              implicitHeight: Widget.height
              iconText: "save"
              text: I18n.tr("Save the sample")
              onClicked: {
                const why = root.editor.saveSample(sampleArea.text);
                root.sampleError = why === "json" ? I18n.tr("Not a JSON object.") : why === "count" ? I18n.tr("{0} samples are kept: remove one first", root.editor.sampleLimits.entries) : why === "size" ? I18n.tr("The samples are over {0} KB: remove one first", root.editor.sampleLimits.bytes / 1024) : "";
                if (why === "")
                  root.editingSample = false;
              }
            }
          }
        }
      }

      // The kept samples, a form row each. By count, over the kept keys
      // (config, never live values)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
          model: root.sampleKeys.length

          FormRow {
            id: sampleRow
            required property int index
            readonly property string key: root.sampleKeys[sampleRow.index] ?? ""
            first: sampleRow.index === 0
            bodyHeight: sampleLine.implicitHeight

            RowLayout {
              id: sampleLine
              width: parent.width
              spacing: Widget.spacing

              StyledLabel {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: sampleRow.key === "" ? I18n.tr("Base") : (root.definition?.module.views.find(v => v.id === sampleRow.key)?.name || sampleRow.key)
                role: "label"
                overflow: "line"
              }
              FlatIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconText: "close"
                tooltipText: I18n.tr("Forget this sample")
                onClicked: root.editor.removeSample(sampleRow.key)
              }
            }
          }
        }
      }
    }

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Actions run")
      description: I18n.tr("The last actions this widget ran, from its buttons, rows, toggles and the test preview. Not saved.")

      ActionLog {}
    }
  }
}
