pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.components.reusable

// The keys axiom binds for some actions (from Keybinds.binds): one row per
// action, with its first key, its label, and a warning when the running
// layer skipped that key because the user's own config holds it
GridLayout {
  id: root

  // [{ action, argument (optional), label }]
  property var entries: []

  columns: 2
  columnSpacing: Widget.spacing * 2
  rowSpacing: Widget.spacing

  function bindFor(entry) {
    return KeybindsConfig.activeBinds.find(bind => bind.action === entry.action && (entry.argument === undefined || String(bind.argument ?? "") === entry.argument)) ?? null;
  }

  Repeater {
    model: root.entries

    delegate: RowLayout {
      id: entryRow
      required property var modelData
      readonly property var bind: root.bindFor(modelData)
      readonly property bool skipped: !!bind && CompositorConfigManager.skippedKeys.includes(bind.key)
      Layout.fillWidth: true
      spacing: Widget.spacing

      KeyHint {
        key: entryRow.bind ? entryRow.bind.key.replace(/\s*\+\s*/g, " + ") : I18n.tr("not bound")
      }

      StyledText {
        Layout.fillWidth: true
        text: entryRow.modelData.label
        elide: Text.ElideRight
      }

      IssueIcon {
        visible: entryRow.skipped
        tip: entryRow.skipped ? I18n.tr("Skipped: your own config binds {0} too", entryRow.bind.key) : ""
      }
    }
  }
}
