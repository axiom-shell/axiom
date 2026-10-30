pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable

/**
 * Settings page, Maintenance (the category's `card`, wide): save the config's
 * look, layout, keybinds, apps and wallpapers under a name, and restore or
 * delete saved ones. Only the active one (last saved or restored) can be
 * overwritten from its row; it's marked Current, with an unsaved dot once
 * the running config differs, and its Restore is Revert (its edits
 * discarded). Overwrite, restore, delete and reverting to the defaults ask
 * for a second click to confirm; an armed restore or apply says in place of
 * its subtitle where the running config goes first, warned when that loses
 * something unless saved by hand (SavedConfigsManager.keepHint). Restoring (a snapshot or
 * the defaults) leaves machine settings as they are. Below them, exporting
 * the look to share and importing a shared file (confirmed on its own row),
 * then the example setups (SavedConfigsManager.examples), applied the same
 * way.
 */
FieldGroup {
  id: root

  description: I18n.tr("Snapshots of the look, layout, keybinds, apps and wallpapers, stored in {0}. Restoring one leaves monitors, accounts, theme integrations and other settings for this PC as they are.", SavedConfigsManager.savedDir)

  // Row awaiting a confirming click: { name, action }. The defaults row uses
  // an empty name, which no saved file can have.
  property var pending: null
  // Where SavedConfigsManager.status shows: under the Share row after an
  // export, import or example, else under the name field
  property bool shareStatus: false

  // An armed restore's or apply's subtitle: where the running config goes
  // first (SavedConfigsManager.keepHint), else `idle`
  component Subtitle: StyledText {
    required property bool armed
    required property string restoring
    property string idle: ""
    readonly property var hint: SavedConfigsManager.keepHint(SavedConfigsManager.keep, restoring)
    readonly property bool hinting: armed && hint.text !== ""
    text: hinting ? hint.text : idle
    textColor: hinting && hint.warning ? Theme.warning : Theme.foreground
    opacity: hinting ? 1 : 0.6
    textSize: Appearance.fontSizeBy(-2)
    elide: Text.ElideRight
    Layout.fillWidth: true
  }

  // The last outcome, shown beside the controls that caused it
  component StatusLine: StyledText {
    required property bool shown
    visible: shown && SavedConfigsManager.status !== ""
    text: SavedConfigsManager.status
    opacity: 0.7
    textSize: Appearance.fontSizeBy(-1)
    Layout.fillWidth: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      id: nameEntry
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("Configuration name")
      onAccepted: root.save()
    }

    StyledTextButton {
      Layout.preferredHeight: Widget.height
      text: I18n.tr(SavedConfigsManager.exists(nameEntry.text) ? "Overwrite" : "Save")
      onClicked: root.save()
    }
  }

  StatusLine {
    shown: !root.shareStatus
  }

  StyledText {
    wrapMode: Text.WordWrap
    visible: SavedConfigsManager.model.count === 0
    text: I18n.tr("No saved configurations yet.")
    opacity: 0.5
    Layout.fillWidth: true
  }

  Repeater {
    model: SavedConfigsManager.model

    delegate: StyledContainer {
      id: row
      required property string fileBaseName
      required property date fileModified
      readonly property bool active: SavedConfigsManager.active === fileBaseName
      readonly property string pendingAction: root.pending?.name === fileBaseName ? root.pending.action : ""

      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height + Widget.padding * 2

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Widget.padding
        anchors.rightMargin: Widget.padding
        spacing: Widget.spacing

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          // The name at its full width while it fits, then elided, with
          // the badges right after it
          Item {
            id: nameLine
            Layout.fillWidth: true
            implicitWidth: nameText.implicitWidth + (badges.visible ? Widget.spacing + badges.implicitWidth : 0)
            implicitHeight: Math.max(nameText.implicitHeight, badges.implicitHeight)

            StyledText {
              id: nameText
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, nameLine.width - (badges.visible ? Widget.spacing + badges.implicitWidth : 0))
              text: row.fileBaseName
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              id: badges
              visible: row.active
              x: nameText.width + Widget.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Widget.spacing

              StatusChip {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent
                text: I18n.tr("Current")
              }

              UnsavedDot {
                anchors.verticalCenter: parent.verticalCenter
                shown: SavedConfigsManager.modified
              }
            }
          }

          Subtitle {
            armed: row.pendingAction === "restore"
            restoring: row.fileBaseName
            idle: I18n.formatDate(row.fileModified, I18n.dateFormat("dateTime"))
          }
        }

        StyledTextButton {
          visible: row.active
          Layout.preferredHeight: Widget.height
          text: I18n.tr(row.pendingAction === "overwrite" ? "Confirm" : "Overwrite")
          onClicked: root.confirm(row.fileBaseName, "overwrite")
        }

        // On the active one, Revert: there's nothing to restore unchanged
        StyledTextButton {
          visible: !row.active || SavedConfigsManager.modified
          Layout.preferredHeight: Widget.height
          text: row.pendingAction === "restore" ? I18n.tr("Confirm") : row.active ? I18n.tr("Revert") : I18n.tr("Restore")
          onClicked: root.confirm(row.fileBaseName, "restore")
        }

        StyledTextButton {
          Layout.preferredHeight: Widget.height
          text: I18n.tr(row.pendingAction === "delete" ? "Confirm" : "Delete")
          hoverColor: Theme.error
          onClicked: root.confirm(row.fileBaseName, "delete")
        }
      }
    }
  }

  StyledContainer {
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height + Widget.padding * 2

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding
      spacing: Widget.spacing

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        StyledText {
          text: I18n.tr("Defaults")
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Subtitle {
          armed: root.pending?.name === "" && root.pending?.action === "restore"
          restoring: ""
          idle: I18n.tr("The look, layout, keybinds and apps a first run starts with")
        }
      }

      StyledTextButton {
        readonly property bool armed: root.pending?.name === "" && root.pending?.action === "restore"
        Layout.preferredHeight: Widget.height
        text: I18n.tr(armed ? "Confirm" : "Restore")
        hoverColor: Theme.error
        onClicked: root.confirm("", "restore")
      }
    }
  }

  SectionHeading {
    Layout.topMargin: Widget.spacing
    title: I18n.tr("Share")
    description: I18n.tr("Export writes the look and layout to a file in your home folder, leaving out monitors, wallpapers, accounts and paths. Import applies such a file (or an example, or a whole config) the way an example applies.")
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    // Off by default: preferences, keybinds and apps are yours, not part
    // of a look to share
    StyledSwitch {
      id: includePersonal
    }

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Include preferences, keybinds and apps")
      elide: Text.ElideRight
    }

    StyledTextButton {
      Layout.preferredHeight: Widget.height
      text: I18n.tr("Export")
      onClicked: {
        root.shareStatus = true;
        SavedConfigsManager.exportConfig(includePersonal.checked, includeCommands.checked);
      }
    }

    StyledTextButton {
      Layout.preferredHeight: Widget.height
      enabled: !SavedConfigsManager.picking
      text: I18n.tr("Import…")
      onClicked: {
        root.shareStatus = true;
        SavedConfigsManager.browseImport();
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    // Off by default too: a shared command runs on whoever takes it
    StyledSwitch {
      id: includeCommands
    }

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Include commands (for a backup or your other PCs)")
      elide: Text.ElideRight
    }
  }

  StatusLine {
    shown: root.shareStatus
  }

  StyledText {
    text: I18n.tr("Only import files from people you trust. An import can also carry preferences, keybinds and apps, and commands, which you're asked about separately (off unless you turn them on): commands run as you, so read every one in the file first.")
    textColor: Theme.warning
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // The imported file, until it's applied or cancelled
  StyledContainer {
    id: importRow
    readonly property var importing: SavedConfigsManager.importing
    visible: importing !== null
    Layout.fillWidth: true
    implicitHeight: importColumn.implicitHeight + Widget.padding * 2
    // Off for each new file: its personal parts and commands come only
    // when asked
    onImportingChanged: {
      takePersonal.checked = false;
      takeCommands.checked = false;
    }

    ColumnLayout {
      id: importColumn
      anchors.fill: parent
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            text: importRow.importing?.title ?? ""
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          StyledText {
            visible: text !== ""
            text: importRow.importing?.description ?? ""
            opacity: 0.6
            textSize: Appearance.fontSizeBy(-2)
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          StyledText {
            text: Paths.shortenHome(importRow.importing?.path ?? "")
            opacity: 0.6
            textSize: Appearance.fontSizeBy(-2)
            elide: Text.ElideMiddle
            Layout.fillWidth: true
          }
        }

        StyledTextButton {
          Layout.preferredHeight: Widget.height
          text: I18n.tr("Apply")
          onClicked: {
            root.shareStatus = true;
            SavedConfigsManager.confirmImport(takePersonal.checked, takeCommands.checked);
          }
        }

        StyledTextButton {
          Layout.preferredHeight: Widget.height
          text: I18n.tr("Cancel")
          onClicked: SavedConfigsManager.cancelImport()
        }
      }

      // Only for a file that holds them: one without would put the
      // defaults in place of the user's own
      RowLayout {
        visible: importRow.importing?.hasPersonal ?? false
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledSwitch {
          id: takePersonal
        }

        StyledText {
          Layout.fillWidth: true
          text: I18n.tr("Also take its preferences, keybinds and apps")
          wrapMode: Text.Wrap
        }
      }

      RowLayout {
        visible: importRow.importing?.hasCommands ?? false
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledSwitch {
          id: takeCommands
        }

        StyledText {
          Layout.fillWidth: true
          text: I18n.tr("Also take its commands")
          wrapMode: Text.Wrap
        }
      }

      StyledText {
        readonly property var hint: SavedConfigsManager.keepHint(SavedConfigsManager.keep, "")
        visible: text !== ""
        text: hint.text
        textColor: hint.warning ? Theme.warning : Theme.foreground
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      StyledText {
        visible: importRow.importing?.hasCommands ?? false
        text: I18n.tr("This file holds commands. They run as you, with your files and accounts, so a file from someone else can do anything you can. Before turning this on, open the file in a text editor and read every command in it, and only take them from a source you trust.")
        textColor: takeCommands.checked ? Theme.error : Theme.warning
        textSize: Appearance.fontSizeBy(-1)
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }
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

    delegate: StyledContainer {
      id: exampleRow
      required property var modelData
      readonly property bool armed: root.pending?.name === "example:" + modelData.name

      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height + Widget.padding * 2

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Widget.padding
        anchors.rightMargin: Widget.padding
        spacing: Widget.spacing

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            text: exampleRow.modelData.title
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          Subtitle {
            visible: text !== ""
            armed: exampleRow.armed
            restoring: ""
            idle: exampleRow.modelData.description
          }
        }

        StyledTextButton {
          Layout.preferredHeight: Widget.height
          text: I18n.tr(exampleRow.armed ? "Confirm" : "Apply")
          onClicked: root.confirm("example:" + exampleRow.modelData.name, "apply")
        }
      }
    }
  }

  function save() {
    root.shareStatus = false;
    SavedConfigsManager.save(nameEntry.text);
    nameEntry.text = "";
    root.pending = null;
  }

  // First click arms the action, a second click on the same button runs it
  function confirm(name, action) {
    if (root.pending?.name !== name || root.pending?.action !== action) {
      root.pending = {
        name: name,
        action: action
      };
      return;
    }
    root.pending = null;
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
