pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.forms
import qs.components.content.parts

// Settings page, General › Default apps (the Apps section's `x-card`):
// which app opens each kind of link and file, and which terminal starts
// (DefaultAppsManager: the user's mimeapps.list and xdg-terminals.list,
// which every app follows, not only axiom): one picker per role
// (DefaultAppPickers), and any other file type by its MIME type. A pick is
// saved at once: it isn't a config edit. The Apps section's commands, when
// set, stand in for the terminal, file manager and browser
PageCard {
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
      tone: "neutral"
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
    role: "caption"
    overflow: "wrap"
  }

  DefaultAppPickers {
    id: pickers
  }

  // -- Any other type --

  FoldFormRow {
    id: other
    title: I18n.tr("Other file types")
    onToggled: other.open = !other.open
  }

  // The lookup and what opens the type it found: one row
  FormRow {
    shown: other.open
    tinted: false
    bodyHeight: lookup.implicitHeight

    ColumnLayout {
      id: lookup
      width: parent.width
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Any type by its MIME name, such as image/x-xcf or application/vnd.oasis.opendocument.text.")
        role: "caption"
        tone: "muted"
        overflow: "wrap"
      }

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
        Layout.fillWidth: true
        visible: root.otherState !== null
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
}
