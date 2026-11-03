pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.forms
import qs.components.content.base
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
    implicitWidth: root.cardPageWidth
    implicitHeight: root.pageHeight

    TitledCard {
      title: I18n.tr("Monitors")
      scrollKey: "Monitors"
      dirty: MonitorManager.isDirty
      canSave: MonitorManager.canApply && !MonitorManager.pending
      saveLabel: MonitorManager.selectedIsLive ? I18n.tr("Apply") : I18n.tr("Save")
      onSave: MonitorManager.apply()
      onReset: MonitorManager.reset()

      headerExtras: RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing * 2

        SchemaComboBox {
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
        }

        StyledTextEntry {
          id: nameField
          Layout.preferredWidth: root.grid.unit * 0.6
          Layout.preferredHeight: Widget.height
          placeholderText: I18n.tr("Layout name")
          // Only typing renames, never a name pushed in (below)
          onTextEdited: MonitorManager.renameProfile(MonitorManager.selectedProfile, nameField.text)

          // StyledTextEntry writes each keystroke back to its `text`, which
          // drops any binding on it, so the name is pushed in instead: on
          // every draft change unless it's being typed, always on a switch
          function syncName(force) {
            if (force || !nameField.input.activeFocus)
              nameField.text = MonitorManager.profiles[MonitorManager.selectedProfile]?.name ?? "";
          }
          Component.onCompleted: syncName(true)
          Connections {
            target: MonitorManager
            function onProfileChanged() {
              nameField.syncName(false);
            }
            function onSelectedProfileChanged() {
              nameField.syncName(true);
            }
          }
        }

        StyledTextButton {
          implicitHeight: Widget.height
          iconText: "add"
          text: I18n.tr("New layout")
          onClicked: MonitorManager.newProfile()
        }

        StyledTextButton {
          visible: MonitorManager.profiles.length > 1
          implicitHeight: Widget.height
          iconText: "delete"
          text: I18n.tr("Delete")
          onClicked: MonitorManager.removeProfile(MonitorManager.selectedProfile)
        }

        Item {
          Layout.fillWidth: true
        }

        StyledTextButton {
          implicitHeight: Widget.height
          iconText: "badge"
          text: I18n.tr("Identify")
          onClicked: MonitorManager.identify()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: root.pageHeight - Widget.height * 6
        spacing: Widget.spacing * 3

        // Both streamed in as the page opens (StreamedLoader)
        StreamedLoader {
          Layout.fillWidth: true
          Layout.fillHeight: true
          label: "monitor canvas"
          sourceComponent: MonitorCanvas {}
        }

        StyledScrollView {
          id: inspectorScroll
          // Its rows (rotation, the steppers) are sized by the font, so
          // on a small card it keeps their width and the canvas gives way
          Layout.preferredWidth: Math.max(root.grid.unit * 0.85, Appearance.fontSize * 24)
          Layout.fillHeight: true
          contentPadding: 0

          StreamedLoader {
            width: inspectorScroll.availableWidth
            label: "monitor inspector"
            sourceComponent: MonitorInspector {
              settingsLinks: root.settingsLinks
            }
          }
        }

        ScrollMemory {
          flickable: inspectorScroll.contentItem as Flickable
          key: "Monitors/inspector"
        }
      }

      StyledText {
        visible: !MonitorManager.selectedIsLive
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: I18n.tr("This layout is for monitors that aren't all connected: saving keeps it for when they are.")
      }

      IssueList {
        issues: MonitorManager.issues
      }

      StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        text: root.modeNote
      }

      SettingsLink {
        id: modeLink
        Layout.fillWidth: true
        visible: root.settingsLinks && modeLink.available
        setting: "Compositor.mode"
      }
    }
  }
}
