pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.parts

// Settings page, General › Default apps (the Apps section's `x-card`):
// which app opens each kind of link and file, and which terminal starts
// (DefaultAppsManager: the user's mimeapps.list and xdg-terminals.list,
// which every app follows, not only axiom): one picker per role
// (DefaultAppPickers), and any other file type by its MIME type. A pick is
// saved at once: it isn't a config edit. The Apps section's commands, when
// set, stand in for the terminal, file manager and browser
FieldGroup {
  id: root

  // Other file types: the MIME type typed, and what opens it
  property string otherMime: ""
  property var otherState: null

  function lookUp() {
    const mime = otherEntry.text.trim();
    root.otherMime = mime;
    root.otherState = null;
    if (/^[\w.+-]+\/[\w.+-]+$/.test(mime))
      DefaultAppsManager.typeState(mime, state => {
        if (root.otherMime === mime)
          root.otherState = state;
      });
  }

  headerExtras: [
    StatusChip {
      shown: DefaultAppsManager.busy
      text: I18n.tr("Saving…")
      color: Theme.foregroundAlt
    },
    StyledIconButton {
      iconText: "refresh"
      tooltipText: I18n.tr("Read again")
      onClicked: DefaultAppsManager.refresh()
    }
  ]

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Every app follows these, not only axiom. A change is saved at once, in your mimeapps.list.")
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.WordWrap
  }

  DefaultAppPickers {
    id: pickers
  }

  // --- Any other type ---

  FoldingSection {
    id: other
    Layout.fillWidth: true
    title: I18n.tr("Other file types")
    description: I18n.tr("Any type by its MIME name, such as image/x-xcf or application/vnd.oasis.opendocument.text.")
    collapsed: true
    onToggled: other.collapsed = !other.collapsed

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledTextEntry {
        id: otherEntry
        Layout.fillWidth: true
        placeholderText: "type/subtype" // not translated: the form to type
        onAccepted: root.lookUp()
      }

      StyledTextButton {
        text: I18n.tr("Look up")
        onClicked: root.lookUp()
      }
    }

    StyledComboEntry {
      visible: root.otherState !== null
      Layout.fillWidth: true
      enabled: !DefaultAppsManager.busy && (root.otherState?.handlers ?? []).length > 0
      value: root.otherState?.default ?? ""
      placeholderText: I18n.tr("No app opens this type")
      options: pickers.optionsOf(root.otherState?.handlers)
      onPicked: value => {
        DefaultAppsManager.setType(root.otherMime, value);
        root.otherState = Object.assign({}, root.otherState, {
          "default": value
        });
      }
    }
  }
}
