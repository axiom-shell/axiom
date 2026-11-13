pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.forms
import qs.components.reusable

// The Special workspaces card's list (Workspaces.specialWorkspaces' `x-row`):
// every special workspace that exists, as edited (SettingsManager.knownSpecials:
// one with an entry, one live, one a bind or hot corner holds), each with its
// id, an icon and a label (setting one makes the entry; an invalid id shows
// as it is), and an X: enabled to delete the entry, greyed with the reasons
// while something uses it (windows open, a bind or hot corner naming it),
// absent for one with no entry. A last row
// adds an entry by its id (SpecialWorkspaces.validId). Edits go through the
// settings draft.
// I18n.tr("Used by keybind {0}")
// I18n.tr("Used by hot corner {0}")
// I18n.tr("Top left")
// I18n.tr("Top right")
// I18n.tr("Bottom left")
// I18n.tr("Bottom right")
ColumnLayout {
  id: root

  // The settings row (SettingsField's `x-row`) and its form
  property var row: null
  property var form: null

  Layout.fillWidth: true
  spacing: Widget.spacing

  readonly property var rows: SettingsManager.knownSpecials
  // The Repeater's model is deliberately live (the list must show the live
  // special workspaces), bounded by keying it on the set of ids: the rows are
  // rebuilt only when that changes, not as windows come and go
  readonly property string _key: JSON.stringify(root.rows.map(r => r.id))
  readonly property var ids: JSON.parse(root._key)

  // Why a row can't be deleted, one reason a line
  function reasonsOf(special) {
    return SpecialWorkspaces.blockers(special).map(b => b.kind === "windows" ? (b.count === 1 ? I18n.tr("1 window open") : I18n.tr("{0} windows open", b.count)) : I18n.tr(b.usedBy, b.translate ? I18n.tr(b.name) : b.name)).join("\n");
  }

  FieldHeader {
    visible: root.row !== null
    label: root.row?.title ?? ""
    description: root.row?.schema?.description ?? ""
  }

  Repeater {
    model: root.ids

    delegate: StyledContainer {
      id: entry
      required property string modelData
      readonly property var special: root.rows.find(r => r.id === entry.modelData) ?? null
      readonly property bool configured: entry.special?.configured === true
      // A valid id: it takes an icon and a label (an entry made as one is set)
      readonly property bool editable: entry.special?.editable === true
      readonly property bool deletable: SpecialWorkspaces.deletable(entry.special)

      Layout.fillWidth: true
      implicitHeight: rowLayout.implicitHeight + Widget.smallPadding * 2
      backgroundColor: Theme.background

      RowLayout {
        id: rowLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Widget.padding
        anchors.rightMargin: Widget.smallPadding
        spacing: Widget.spacing

        StyledLabel {
          Layout.fillWidth: !entry.editable
          Layout.preferredWidth: entry.editable ? Widget.px(120) : -1
          elide: Text.ElideRight
          text: entry.modelData
        }

        IconEntry {
          visible: entry.editable
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.alignment: Qt.AlignTop
          value: entry.special?.icon ?? ""
          onPicked: value => SettingsManager.setSpecialWorkspace(entry.modelData, value, entry.special?.label ?? "")
        }

        SchemaTextField {
          visible: entry.editable
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.alignment: Qt.AlignTop
          label: ""
          placeholderText: I18n.tr("Text")
          currentConfigValue: entry.special?.label ?? ""
          onValueEdited: value => SettingsManager.setSpecialWorkspace(entry.modelData, entry.special?.icon ?? "", value)
        }

        StyledIconButton {
          visible: entry.configured && entry.deletable
          iconText: "close"
          tooltipText: I18n.tr("Remove")
          hoverColor: Theme.error
          size: Widget.height - Widget.px(4)
          onClicked: SettingsManager.removeSpecialWorkspace(entry.modelData)
        }

        // Greyed while something uses it, saying what on hover (a disabled
        // button never hears the hover)
        Item {
          visible: entry.configured && !entry.deletable
          Layout.preferredWidth: Widget.height - Widget.px(4)
          Layout.preferredHeight: Widget.height - Widget.px(4)

          StyledIcon {
            anchors.centerIn: parent
            text: "close"
            textColor: Theme.foreground
            opacity: 0.4
          }

          HoverHandler {
            id: blockedHover
          }

          LazyLoader {
            active: blockedHover.hovered

            StyledToolTip {
              target: blockedHover.parent
              text: root.reasonsOf(entry.special)
            }
          }
        }
      }
    }
  }

  // Adding an entry by its id
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      id: addEntry
      readonly property bool valid: SpecialWorkspaces.validId(addEntry.text) && !root.rows.some(r => r.configured && r.id === addEntry.text)
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("New special workspace id")
      onAccepted: {
        if (addEntry.valid)
          root.add(addEntry.text);
      }
    }

    StyledIconButton {
      iconText: "add"
      tooltipText: I18n.tr("Add")
      enabled: addEntry.valid
      size: Widget.height - Widget.px(4)
      onClicked: root.add(addEntry.text)
    }
  }

  function add(id) {
    if (SettingsManager.addSpecialWorkspace(id))
      addEntry.text = "";
  }
}
