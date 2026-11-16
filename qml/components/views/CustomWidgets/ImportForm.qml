pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Custom widgets page, the inspector pane while importing: paste what
// another person copied (a custom widget, or a few) or a Waybar `custom/*`
// module (a block, or a whole config), Check it, and read every command it
// would run before anything is added: nothing is added or run until
// Import. Each definition goes through CustomWidgetsEditor.add with a fresh
// id.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  // CustomWidgetData.readImport of the pasted text, null before a Check
  property var result: null
  // The commands, a definition at a time, as lines to read
  readonly property string commandLines: {
    const lines = [];
    for (const def of root.result?.definitions ?? []) {
      lines.push("# " + (def.name || I18n.tr("Custom widget")));
      const commands = CustomWidgetData.commandsOf(def);
      commands.forEach(c => lines.push(c.where + ": " + c.command));
      if (commands.length === 0)
        lines.push(I18n.tr("(no commands)"));
    }
    return lines.join("\n");
  }
  readonly property bool runsCommands: (root.result?.definitions ?? []).some(def => CustomWidgetData.commandsOf(def).length > 0)

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  // The text for a CustomWidgetData.readImport error code
  function errorText(code, detail) {
    if (code === "json")
      return I18n.tr("Not valid JSON: {0}", detail);
    if (code === "notWidget")
      return I18n.tr("Not a custom widget.");
    if (code === "newer")
      return I18n.tr("Made by a newer version of axiom.");
    if (code === "noModule")
      return I18n.tr("Not a custom widget: it has no module and no command.");
    if (code === "empty")
      return I18n.tr("Nothing in it.");
    return I18n.tr("Not a custom widget or a Waybar custom module.");
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Import a widget")
    description: I18n.tr("Paste a custom widget someone copied with Copy, or a custom/… module from a Waybar config (or the whole config). Nothing is added or run until you press Import.")

    StyledTextArea {
      id: paste
      Layout.fillWidth: true
      expandable: true
      input.font.family: "monospace"
      placeholderText: I18n.tr("Paste here")
      onTextEdited: root.result = null
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.space2
      spacing: Widget.spacing

      StyledTextButton {
        implicitHeight: Widget.height
        enabled: paste.text.trim() !== ""
        iconText: "fact_check"
        text: I18n.tr("Check")
        onClicked: root.result = CustomWidgetData.readImport(paste.text)
      }
      StyledTextButton {
        implicitHeight: Widget.height
        iconText: "close"
        text: I18n.tr("Cancel")
        onClicked: root.editor.importing = false
      }
    }

    Notice {
      visible: root.result !== null && root.result.error !== ""
      Layout.topMargin: Style.space2
      status: "error"
      title: I18n.tr("Couldn't read it")
      text: root.errorText(root.result?.error ?? "", root.result?.detail ?? "")
    }

    // A good paste: what it would run
    Notice {
      visible: root.result !== null && root.result.error === ""
      Layout.topMargin: Style.space2
      status: root.runsCommands ? "warning" : "success"
      title: root.runsCommands ? I18n.tr("This widget runs commands") : I18n.tr("This widget runs no commands")
      text: root.result?.kind === "waybar" ? I18n.tr("A Waybar module: its exec runs as the widget's script.") : I18n.tr("They run when the widget is shown, as you set it up here.")
    }
    StyledText {
      visible: root.result !== null && root.result.error === ""
      Layout.fillWidth: true
      Layout.topMargin: Style.space2
      text: root.commandLines
      textFamily: "monospace"
      role: "caption"
      overflow: "wrap"
    }
    StyledTextButton {
      visible: root.result !== null && root.result.error === ""
      Layout.topMargin: Style.space2
      implicitHeight: Widget.height
      iconText: "download"
      text: I18n.tr("Import")
      onClicked: root.editor.importDefinitions(root.result.definitions)
    }
  }
}
