pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable

// One picker per default app role (DefaultAppsManager.roleList, or those
// of `roles`): its icon, name, and the installed apps that open it, the
// default chosen; a pick is saved at once (the user's mimeapps.list). Under
// a role the Apps section's command stands in for, a line says so.
// Settings' Default apps card and the onboarder's Apps page
ColumnLayout {
  id: root

  // Role ids to show (empty: every one)
  property var roles: []

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
      // The Apps section's command standing in for this role ("" none)
      // reads: Apps.terminal, Apps.fileManager, Apps.browser
      readonly property string override: row.modelData.id === "terminal" ? Apps.terminal : row.modelData.id === "fileManager" ? Apps.fileManager : row.modelData.id === "browser" ? Apps.browser : ""
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

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
          enabled: DefaultAppsManager.loaded && !DefaultAppsManager.busy && (row.roleState?.handlers ?? []).length > 0
          value: row.roleState?.default ?? ""
          placeholderText: DefaultAppsManager.loaded ? I18n.tr("None installed") : I18n.tr("Reading…")
          options: root.optionsOf(row.roleState?.handlers)
          onPicked: value => {
            if (value !== (row.roleState?.default ?? ""))
              DefaultAppsManager.setDefault(row.modelData.id, value);
          }
        }

        // Some of the role's types open elsewhere: said on hover, as
        // nearly every system has a few
        TipIcon {
          visible: row.roleState?.mixed === true && row.override === ""
          text: "call_split"
          textColor: Theme.foregroundAlt
          tip: I18n.tr("Some of these files open in other apps; picking one sets them all.")
        }
      }

      StyledText {
        visible: row.override !== ""
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.fontSize * 1.6
        text: I18n.tr("axiom runs {0} instead (App commands).", row.override)
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
