pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.views.base

// The monitors page: layout profiles (one per set of monitors, picked by
// what's connected), each a layout to drag monitors around in and the
// selected monitor's settings. Apply tries the profile at once and asks to
// keep it (MonitorManager); a profile for monitors that aren't connected
// is only saved.
BaseView {
  id: root

  Component.onCompleted: {
    MonitorManager.pageShown = true;
    MonitorManager.ensureLoaded();
  }
  Component.onDestruction: MonitorManager.pageShown = false

  // Whether its settings links show: off in the onboarder, where
  // following one would open the overlay over it
  property bool settingsLinks: true

  // Whether the layout's name is being typed in place of the picker
  property bool renaming: false

  function startRename() {
    nameField.text = MonitorManager.profiles[MonitorManager.selectedProfile]?.name ?? "";
    root.renaming = true;
    nameField.input.forceActiveFocus();
    nameField.input.selectAll();
  }

  // Where the compositor gets the profiles from, per Compositor.mode
  readonly property string modeNote: {
    switch (CompositorConfig.mode) {
    case "included":
      return I18n.tr("Saved into axiom's module, which your compositor's config loads.");
    case "managed":
      return I18n.tr("Saved into the config axiom manages; your own files load after it.");
    }
    return I18n.tr("Applied by axiom while it runs: your compositor's own config sets the monitors until then.");
  }

  Item {
    // pageWidth like every tool page; cardPageWidth where the onboarder
    // embeds it (settingsLinks off)
    implicitWidth: root.settingsLinks ? root.pageWidth : root.cardPageWidth
    implicitHeight: root.pageHeight

    // The entry renames the selected layout: another one selected under it
    // (Delete, a monitor plugged in) ends the rename
    Connections {
      target: MonitorManager
      function onSelectedProfileChanged() {
        root.renaming = false;
      }
    }

    ToolPane {
      id: pane
      anchors.fill: parent
      title: I18n.tr("Monitors")
      headerIcon: "monitor"
      scrollKey: "Monitors"
      // Unsaved, or not what the monitors show: Apply puts it on;
      // Discard only for unsaved edits
      dirty: MonitorManager.isDirty || MonitorManager.differsFromLive
      canReset: MonitorManager.isDirty
      canSave: MonitorManager.canApply && !MonitorManager.pending
      saveLabel: MonitorManager.selectedIsLive ? I18n.tr("Apply") : I18n.tr("Save")
      onSave: MonitorManager.apply()
      onReset: MonitorManager.reset()

      toolbar: ToolBar {
        leading: [
          // The layout picker, or its name while renaming (Enter saves,
          // Escape cancels)
          SchemaComboBox {
            visible: !root.renaming
            label: ""
            Layout.fillWidth: false
            Layout.preferredWidth: root.grid.unit * 0.7
            options: MonitorManager.profiles.map((_, index) => String(index))
            optionLabels: MonitorManager.profiles.reduce((labels, profile, index) => {
              labels[String(index)] = index === MonitorManager.liveProfile ? I18n.tr("{0} (connected)", profile.name) : profile.name;
              return labels;
            }, {})
            currentValue: String(MonitorManager.selectedProfile)
            onSelectionChanged: value => MonitorManager.selectProfile(Number(value))
          },
          StyledTextEntry {
            id: nameField
            visible: root.renaming
            Layout.preferredWidth: root.grid.unit * 0.7
            Layout.preferredHeight: Widget.height
            placeholderText: I18n.tr("Layout name")
            onAccepted: {
              MonitorManager.renameProfile(MonitorManager.selectedProfile, nameField.text);
              root.renaming = false;
            }
            input.Keys.onEscapePressed: root.renaming = false
            // Leaving it cancels
            input.onActiveFocusChanged: if (!nameField.input.activeFocus)
              root.renaming = false
          },
          StyledIconButton {
            iconText: "edit"
            tooltipText: I18n.tr("Rename this layout")
            onClicked: root.startRename()
          },
          StyledIconButton {
            visible: MonitorManager.profiles.length > 1
            kind: "danger"
            iconText: "delete"
            tooltipText: I18n.tr("Delete this layout")
            onClicked: MonitorManager.removeProfile(MonitorManager.selectedProfile)
          }
        ]
        trailing: [
          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "add"
            text: I18n.tr("New layout")
            onClicked: {
              // Made at once with its default name, which the entry asks to
              // change
              MonitorManager.newProfile();
              root.startRename();
            }
          },
          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "badge"
            text: I18n.tr("Identify")
            onClicked: ActionsManager.run("monitorsIdentify")
          }
        ]
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: pane.bodyHeight
        spacing: Widget.spacing * 3

        // The canvas is the pane's only main content: no box of its own
        // (its Apply and name are the pane's header). Both streamed in as
        // the page opens (StreamedLoader)
        WorkArea {
          embedded: true
          showActions: false
          Layout.fillWidth: true
          Layout.fillHeight: true

          StreamedLoader {
            anchors.fill: parent
            label: "monitor canvas"
            sourceComponent: MonitorCanvas {}
          }
        }

        StyledSeparator {
          Layout.fillHeight: true
          Layout.preferredWidth: Style.dividerWidth
        }

        CardScroll {
          id: inspectorScroll
          // Its rows (rotation, the steppers) are sized by the font, so
          // on a small card it keeps their width and the canvas gives way
          Layout.preferredWidth: Math.max(root.grid.unit * 0.85, Appearance.fontSize * 24)
          Layout.fillHeight: true

          StreamedLoader {
            Layout.fillWidth: true
            label: "monitor inspector"
            sourceComponent: MonitorInspector {
              settingsLinks: root.settingsLinks
            }
          }
        }

        ScrollMemory {
          flickable: inspectorScroll.flickable as Flickable
          key: "Monitors/inspector"
        }
      }

      footer: [
        StyledText {
          visible: !MonitorManager.selectedIsLive
          Layout.fillWidth: true
          overflow: "wrap"
          tone: "muted"
          text: I18n.tr("This layout is for monitors that aren't all connected: saving keeps it for when they are.")
        },
        IssueList {
          issues: MonitorManager.issues
        },
        StyledText {
          Layout.fillWidth: true
          overflow: "wrap"
          role: "caption"
          tone: "muted"
          text: root.modeNote
        },
        SettingsLink {
          id: modeLink
          Layout.fillWidth: true
          visible: root.settingsLinks && modeLink.available
          setting: "Compositor.mode"
        }
      ]
    }
  }
}
