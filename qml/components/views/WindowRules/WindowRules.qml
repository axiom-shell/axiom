pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.views.base

// The Window rules page (docs/dev/features/window-rules.md): the rules as a
// list, dragged to order (the higher one wins), and beside it the selected
// rule: what it's for, which windows, and what happens when one opens. Edits
// go through WindowRulesManager.editor's draft and reach the compositor when
// saved.
BaseView {
  id: root

  readonly property var editor: WindowRulesManager.editor

  Component.onCompleted: {
    root.editor.ensureLoaded();
    root.editor.acquire(root);
  }
  Component.onDestruction: root.editor.release(root)

  StreamedLoader {
    Layout.preferredWidth: root.sideWidth
    Layout.preferredHeight: root.pageHeight
    label: "window rules list"
    sourceComponent: RulesPanel {}
  }

  Item {
    implicitWidth: root.editorWidth
    implicitHeight: root.pageHeight

    ToolPane {
      id: pane
      anchors.fill: parent
      // The kind of pane, never the selection's name (that is the header's)
      title: I18n.tr("Rule")
      headerIcon: "select_window"
      scrollKey: "WindowRules/" + root.editor.selectedId
      dirty: root.editor.isDirty
      onSave: root.editor.save()
      onReset: root.editor.reset()

      emptyKind: root.editor.selected !== null ? "" : "none"
      emptyIcon: "select_window"
      emptyText: I18n.tr("No rules yet.")
      emptyHint: I18n.tr("Add a rule on the left: pick which windows it's for, then what happens when one opens.")

      pinned: Loader {
        active: root.editor.selected !== null
        visible: active
        Layout.fillWidth: true

        sourceComponent: InspectorHeader {
          id: header
          readonly property bool isOn: root.editor.selected?.enabled !== false
          readonly property int openCount: root.editor.openCount(root.editor.selectedIndex)

          icon: root.editor.selected?.icon || "select_window"
          title: root.editor.selected?.name || root.editor.selected?.id || ""
          subtitle: openCount > 0 ? I18n.tr("{0} open", openCount) : ""
          canDuplicate: true
          duplicateTooltip: I18n.tr("Copy this rule")
          canRemove: true
          removeTooltip: I18n.tr("Remove this rule")
          onDuplicate: root.editor.duplicate(root.editor.selectedIndex)
          onRemove: root.editor.remove(root.editor.selectedIndex)

          StyledIconButton {
            kind: header.isOn ? "primary" : "tonal"
            iconText: header.isOn ? "toggle_on" : "toggle_off"
            tooltipText: header.isOn ? I18n.tr("Turn off") : I18n.tr("Turn on")
            onClicked: root.editor.setEnabled(root.editor.selectedIndex, !header.isOn)
          }
        }
      }

      // A ColumnLayout's Repeater re-runs on every draft edit: built once a
      // rule is selected, keyed by it
      KeyedLoader {
        id: inspector
        Layout.fillWidth: true
        Layout.preferredHeight: inspector.childrenRect.height
        key: root.editor.selectedId

        sourceComponent: RuleInspector {
          width: inspector.width
        }
      }
    }
  }
}
