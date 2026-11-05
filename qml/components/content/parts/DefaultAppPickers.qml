pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable

// One picker per default app role (DefaultAppsManager.roleList, or those
// of `roles`): its icon, name, and the installed apps that open it, the
// default chosen; a pick is saved at once (the user's mimeapps.list). Each
// also offers a command of axiom's own (Apps.commands, by role id), typed
// in a field under the picker and saved at once too; picking an app
// clears it.
// Settings' Default apps card and the onboarder's Apps page
ColumnLayout {
  id: root

  // Role ids to show (empty: every one)
  property var roles: []

  // The picker's choice standing for a command (no desktop entry id has
  // a colon first)
  readonly property string commandChoice: ":command"

  function optionsOf(handlers) {
    return (handlers ?? []).map(entry => ({
          "value": entry.id,
          "label": entry.name,
          "image": DefaultAppsManager.iconOf(entry)
        }));
  }

  Component.onCompleted: DefaultAppsManager.refresh()

  Layout.fillWidth: true
  spacing: Widget.spacing

  Repeater {
    model: DefaultAppsManager.roleList.filter(role => root.roles.length === 0 || root.roles.includes(role.id))

    delegate: ColumnLayout {
      id: row
      required property var modelData
      readonly property var roleState: DefaultAppsManager.roles[row.modelData.id] ?? null
      // The Apps setting holding this role's command
      readonly property string commandKey: "Apps.commands." + row.modelData.id
      // The command axiom runs in place of the default app ("" none)
      readonly property string command: Apps.commands[row.modelData.id] ?? ""
      // "Custom command…" picked, its field open before anything is saved
      property bool commandPicked: false
      readonly property bool commandShown: row.command !== "" || row.commandPicked
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      function pick(value) {
        if (value === root.commandChoice) {
          row.commandPicked = true;
          commandEntry.text = row.command;
          commandEntry.input.forceActiveFocus();
          return;
        }
        row.commandPicked = false;
        if (row.command !== "")
          SettingsManager.commitValues({
            [row.commandKey]: ""
          });
        if (value !== (row.roleState?.default ?? ""))
          DefaultAppsManager.setDefault(row.modelData.id, value);
      }

      // The typed command saved; empty goes back to the default app
      function saveCommand() {
        const typed = commandEntry.text.trim();
        if (typed !== row.command)
          SettingsManager.commitValues({
            [row.commandKey]: typed
          });
        row.commandPicked = typed !== "";
      }

      onCommandChanged: commandEntry.text = row.command

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          text: row.modelData.icon
          textColor: Theme.accent
        }

        StyledText {
          Layout.preferredWidth: Widget.px(130)
          // I18n.tr: the labels are declared in DefaultAppsManager
          text: I18n.tr(row.modelData.label)
          elide: Text.ElideRight
        }

        StyledComboEntry {
          Layout.fillWidth: true
          enabled: DefaultAppsManager.loaded && !DefaultAppsManager.busy
          value: row.commandShown ? root.commandChoice : row.roleState?.default ?? ""
          placeholderText: DefaultAppsManager.loaded ? I18n.tr("None installed") : I18n.tr("Reading…")
          options: root.optionsOf(row.roleState?.handlers).concat([
            {
              "value": root.commandChoice,
              "label": I18n.tr("Custom command…"),
              "icon": "terminal"
            }
          ])
          onPicked: value => row.pick(value)
        }

        // Some of the role's types open elsewhere: said on hover, as
        // nearly every system has a few
        TipIcon {
          visible: row.roleState?.mixed === true && !row.commandShown
          text: "call_split"
          textColor: Theme.foregroundAlt
          tip: I18n.tr("Some of these files open in other apps; picking one sets them all.")
        }
      }

      // --- The command, typed ---

      RowLayout {
        visible: row.commandShown
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.fontSize * 1.6
        spacing: Widget.spacing

        StyledTextEntry {
          id: commandEntry
          Layout.fillWidth: true
          text: row.command
          placeholderText: row.modelData.id === "terminal" ? I18n.tr("A command, such as foot") : I18n.tr("A command, such as firefox --new-window")
          onAccepted: row.saveCommand()
        }

        StyledTextButton {
          text: I18n.tr("Save")
          enabled: commandEntry.text.trim() !== row.command
          onClicked: row.saveCommand()
        }
      }

      StyledText {
        visible: row.commandShown
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.fontSize * 1.6
        text: row.modelData.id === "terminal" ? I18n.tr("For terminal apps axiom runs: command -e program. Other apps still open the default terminal.") : I18n.tr("axiom starts it given what it opens (links, folders or files). Other apps still open the default.")
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
      }
    }
  }

  StyledText {
    visible: DefaultAppsManager.error !== ""
    Layout.fillWidth: true
    text: DefaultAppsManager.error
    textColor: Theme.error
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
  }
}
