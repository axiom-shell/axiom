pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.forms

/**
 * Settings page, System (the category's `card`, wide): save the config's
 * look, layout, keybinds, apps and wallpapers under a name, and restore or
 * delete saved ones. Only the active one (last saved or restored, always
 * there) can be overwritten from its row, and only the others deleted; it's
 * marked Current, with an unsaved dot once the running config differs, and
 * its Restore is Revert (its edits discarded). Overwrite, restore, delete
 * and reverting to the defaults ask for a second click to confirm (a ConfirmGate: the
 * arming waits for the second press); an
 * armed restore or apply says in place of its subtitle where the running
 * config goes first (SavedConfigsManager.keepHint). Restoring (a snapshot
 * or the defaults) leaves machine settings as they are. Below them, exporting
 * the look to share and importing a shared file (confirmed on its own row),
 * then the example setups (SavedConfigsManager.examples), applied the same
 * way.
 */
PageCard {
  id: root

  description: I18n.tr("Snapshots of the look, layout, keybinds, apps and wallpapers, stored in {0}. Restoring one leaves monitors, accounts, theme integrations and other settings for this PC as they are.", SavedConfigsManager.savedDir)

  // Which action waits for its confirming click: the gate's key (`keyOf`)
  ConfirmGate {
    id: gate
    timeout: 0
  }
  // The share options: what an export includes, what an import takes (the
  // latter off for each new file)
  property bool includePersonal: false
  property bool includeCommands: false
  property bool takePersonal: false
  property bool takeCommands: false
  // Where SavedConfigsManager.status shows: under the Share row after an
  // export, import or example, else under the name field
  property bool shareStatus: false

  // An armed restore's or apply's subtitle: where the running config goes
  // first (SavedConfigsManager.keepHint), else `idle`
  component Subtitle: StyledText {
    required property bool armed
    required property string restoring
    property string idle: ""
    readonly property string hint: SavedConfigsManager.keepHint(restoring)
    readonly property bool hinting: armed && hint !== ""
    text: hinting ? hint : idle
    tone: hinting ? "text" : "muted"
    role: "caption"
    overflow: hinting ? "wrap" : "line"
    Layout.fillWidth: true
  }

  // One item box: the text items (`info`, a title and a subtitle) at the
  // left, the `buttons` at the right. Its height follows its text, so a
  // wrapped hint grows the row; a one-line row keeps one control's height.
  component ConfigRow: ItemBox {
    property alias info: infoColumn.data
    property alias buttons: rowLayout.data

    RowLayout {
      id: rowLayout
      Layout.fillWidth: true
      Layout.minimumHeight: Widget.height
      spacing: Widget.spacing

      ColumnLayout {
        id: infoColumn
        Layout.fillWidth: true
        spacing: 0
      }
    }
  }

  // The key an action's confirming click is armed under
  function keyOf(name, action) {
    return action + ":" + name;
  }

  SubmitEntry {
    id: nameEntry
    placeholderText: I18n.tr("Configuration name")
    // I18n.tr("Overwrite")
    // I18n.tr("Save")
    buttonText: I18n.tr(SavedConfigsManager.exists(nameEntry.text) ? "Overwrite" : "Save")
    canSubmit: true
    onSubmitted: root.save()
  }

  // The last outcome, shown beside the controls that caused it
  StatusLine {
    visible: !root.shareStatus && SavedConfigsManager.status !== ""
    text: SavedConfigsManager.status
    role: "caption"
    Layout.fillWidth: true
  }

  StyledText {
    overflow: "wrap"
    visible: SavedConfigsManager.model.count === 0
    text: I18n.tr("No saved configurations yet.")
    tone: "faint"
    Layout.fillWidth: true
  }

  Repeater {
    model: SavedConfigsManager.model

    delegate: ConfigRow {
      id: row
      required property string fileBaseName
      required property date fileModified
      readonly property bool active: SavedConfigsManager.active === fileBaseName
      readonly property string pendingAction: ["overwrite", "restore", "delete"].find(action => gate.armed === root.keyOf(row.fileBaseName, action)) ?? ""

      info: [
        // The name at its full width while it fits, then elided, with
        // the badges right after it
        Item {
          id: nameLine
          Layout.fillWidth: true
          implicitWidth: nameText.implicitWidth + (badges.visible ? Widget.spacing + badges.implicitWidth : 0)
          implicitHeight: Math.max(nameText.implicitHeight, badges.implicitHeight)

          StyledLabel {
            id: nameText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, nameLine.width - (badges.visible ? Widget.spacing + badges.implicitWidth : 0))
            text: row.fileBaseName
            role: "label"
            overflow: "line"
          }

          Row {
            id: badges
            visible: row.active
            x: nameText.width + Widget.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Widget.spacing

            StatusChip {
              anchors.verticalCenter: parent.verticalCenter
              tone: "accent"
              text: I18n.tr("Current")
            }

            UnsavedDot {
              anchors.verticalCenter: parent.verticalCenter
              shown: SavedConfigsManager.modified
            }
          }
        },
        Subtitle {
          armed: row.pendingAction === "restore"
          restoring: row.fileBaseName
          idle: I18n.formatDate(row.fileModified, I18n.dateTimeFormat())
        }
      ]

      buttons: [
        StyledTextButton {
          visible: row.active
          text: I18n.tr(row.pendingAction === "overwrite" ? "Confirm" : "Overwrite")
          onClicked: root.confirm(row.fileBaseName, "overwrite")
        },
        // On the active one, Revert: there's nothing to restore unchanged
        StyledTextButton {
          visible: !row.active || SavedConfigsManager.modified
          text: row.pendingAction === "restore" ? I18n.tr("Confirm") : row.active ? I18n.tr("Revert") : I18n.tr("Restore")
          onClicked: root.confirm(row.fileBaseName, "restore")
        },
        // Not the active one: one is always active
        StyledTextButton {
          visible: !row.active
          text: I18n.tr(row.pendingAction === "delete" ? "Confirm" : "Delete")
          kind: "danger"
          onClicked: root.confirm(row.fileBaseName, "delete")
        }
      ]
    }
  }

  ConfigRow {
    id: defaultsRow

    readonly property bool armed: gate.armed === root.keyOf("", "restore")

    info: [
      StyledLabel {
        text: I18n.tr("Defaults")
        role: "label"
        overflow: "line"
        Layout.fillWidth: true
      },
      Subtitle {
        armed: defaultsRow.armed
        restoring: ""
        idle: I18n.tr("The look, layout, keybinds and apps a first run starts with")
      }
    ]

    buttons: [
      StyledTextButton {
        text: I18n.tr(defaultsRow.armed ? "Confirm" : "Restore")
        kind: "danger"
        onClicked: root.confirm("", "restore")
      }
    ]
  }

  SectionHeading {
    Layout.topMargin: Widget.spacing
    title: I18n.tr("Share")
    description: I18n.tr("Export writes the look and layout to a file in your home folder, leaving out monitors, wallpapers, accounts and paths. Import applies such a file (or an example, or a whole config) the way an example applies.")
  }

  // Off by default: preferences, keybinds and apps are yours, not part of a
  // look to share
  SwitchRow {
    label: I18n.tr("Include preferences, keybinds and apps")
    checked: root.includePersonal
    onToggled: newValue => root.includePersonal = newValue
  }

  // Off by default too: a shared command runs on whoever takes it
  SwitchRow {
    label: I18n.tr("Include commands (for a backup or your other PCs)")
    checked: root.includeCommands
    onToggled: newValue => root.includeCommands = newValue
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      text: I18n.tr("Export")
      onClicked: {
        root.shareStatus = true;
        SavedConfigsManager.exportConfig(root.includePersonal, root.includeCommands);
      }
    }

    StyledTextButton {
      enabled: !SavedConfigsManager.picking
      text: I18n.tr("Import…")
      onClicked: {
        root.shareStatus = true;
        SavedConfigsManager.browseImport();
      }
    }
  }

  StatusLine {
    visible: root.shareStatus && SavedConfigsManager.status !== ""
    text: SavedConfigsManager.status
    role: "caption"
    Layout.fillWidth: true
  }

  StatusLine {
    text: I18n.tr("Only import files from people you trust. An import can also carry preferences, keybinds and apps, and commands, which you're asked about separately (off unless you turn them on): commands run as you, so read every one in the file first.")
    tone: "warning"
    Layout.fillWidth: true
  }

  // The imported file, until it's applied or cancelled
  ItemBox {
    id: importRow
    readonly property var importing: SavedConfigsManager.importing
    visible: importing !== null
    // Off for each new file: its personal parts and commands come only
    // when asked
    onImportingChanged: {
      root.takePersonal = false;
      root.takeCommands = false;
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledLabel {
          text: importRow.importing?.title ?? ""
          role: "label"
          overflow: "line"
          Layout.fillWidth: true
        }

        StyledLabel {
          visible: text !== ""
          text: importRow.importing?.description ?? ""
          tone: "muted"
          role: "caption"
          overflow: "line"
          Layout.fillWidth: true
        }

        StyledLabel {
          text: Paths.shortenHome(importRow.importing?.path ?? "")
          tone: "muted"
          role: "caption"
          overflow: "line"
          elide: Text.ElideMiddle // style-exempt: middle elides an identifier, keeping its end
          Layout.fillWidth: true
        }
      }

      StyledTextButton {
        text: I18n.tr("Apply")
        onClicked: {
          root.shareStatus = true;
          SavedConfigsManager.confirmImport(root.takePersonal, root.takeCommands);
        }
      }

      StyledTextButton {
        text: I18n.tr("Cancel")
        onClicked: SavedConfigsManager.cancelImport()
      }
    }

    // Only for a file that holds them: one without would put the
    // defaults in place of the user's own
    SwitchRow {
      visible: importRow.importing?.hasPersonal ?? false
      label: I18n.tr("Also take its preferences, keybinds and apps")
      checked: root.takePersonal
      onToggled: newValue => root.takePersonal = newValue
    }

    SwitchRow {
      visible: importRow.importing?.hasCommands ?? false
      label: I18n.tr("Also take its commands")
      checked: root.takeCommands
      onToggled: newValue => root.takeCommands = newValue
    }

    StatusLine {
      visible: text !== ""
      text: SavedConfigsManager.keepHint("")
      role: "caption"
      Layout.fillWidth: true
    }

    StatusLine {
      visible: importRow.importing?.hasCommands ?? false
      text: I18n.tr("This file holds commands. They run as you, with your files and accounts, so a file from someone else can do anything you can. Before turning this on, open the file in a text editor and read every command in it, and only take them from a source you trust.")
      tone: root.takeCommands ? "error" : "warning"
      Layout.fillWidth: true
    }
  }

  SectionHeading {
    visible: SavedConfigsManager.examples.length > 0
    Layout.topMargin: Widget.spacing
    title: I18n.tr("Example setups")
    description: I18n.tr("Apply an example's look and layout: bars, pages, menus, docks and the theme. Wallpapers, monitors, apps and accounts stay as they are. It's saved as a configuration of its own, and changes to the current one are saved first.")
  }

  Repeater {
    model: SavedConfigsManager.examples

    delegate: ConfigRow {
      id: exampleRow
      required property var modelData
      readonly property bool armed: gate.armed === root.keyOf("example:" + modelData.name, "apply")

      info: [
        StyledLabel {
          text: exampleRow.modelData.title
          role: "label"
          overflow: "line"
          Layout.fillWidth: true
        },
        Subtitle {
          visible: text !== ""
          armed: exampleRow.armed
          restoring: ""
          idle: exampleRow.modelData.description
        }
      ]

      buttons: [
        StyledTextButton {
          text: I18n.tr(exampleRow.armed ? "Confirm" : "Apply")
          onClicked: root.confirm("example:" + exampleRow.modelData.name, "apply")
        }
      ]
    }
  }

  function save() {
    root.shareStatus = false;
    SavedConfigsManager.save(nameEntry.text);
    nameEntry.text = "";
    gate.disarm();
  }

  // First click arms the action, a second click on the same button runs it
  function confirm(name, action) {
    if (!gate.pass(root.keyOf(name, action), true))
      return;
    root.shareStatus = action === "apply";
    if (action === "apply")
      SavedConfigsManager.applyExample(name.slice("example:".length));
    else if (action === "restore" && name === "")
      SavedConfigsManager.restoreDefaults();
    else if (action === "restore")
      SavedConfigsManager.restore(name);
    else if (action === "overwrite")
      SavedConfigsManager.save(name);
    else
      SavedConfigsManager.remove(name);
  }
}
