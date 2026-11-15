pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.views.base

// The Custom widgets page (docs/dev/features/custom-widgets.md): the
// definitions and the selected one's script on the left; on the right its
// data (the script's output, and which part of it each field reads), its
// bar look and its module, each a tab (or, while importing, the Import form). Edits go through
// CustomWidgetsManager.editor's draft and show live on the bars and pages.
BaseView {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var tabNames: [I18n.tr("Data"), I18n.tr("Bar"), I18n.tr("Module")]

  Component.onCompleted: {
    root.editor.ensureLoaded();
    root.editor.pageShown = root.visible;
  }
  onVisibleChanged: root.editor.pageShown = root.visible
  Component.onDestruction: root.editor.pageShown = false

  StreamedLoader {
    Layout.preferredWidth: root.sideWidth
    Layout.preferredHeight: root.pageHeight
    label: "custom widgets list"
    sourceComponent: DefinitionsPanel {}
  }

  Item {
    implicitWidth: root.editorWidth
    implicitHeight: root.pageHeight

    ToolPane {
      id: pane
      anchors.fill: parent
      // The kind of pane, never the selection's name (that is the header's)
      title: I18n.tr("Custom widget")
      headerIcon: "widgets"
      scrollKey: "CustomWidgets/" + root.editor.tab
      dirty: root.editor.isDirty
      onSave: root.editor.save()
      onReset: root.editor.reset()

      tabModel: root.editor.selected !== null && !root.editor.importing ? root.tabNames : []
      tabIndex: root.editor.tab
      onTabClicked: index => root.editor.selectTab(index)

      emptyKind: root.editor.selected !== null || root.editor.importing ? "" : root.editor.items.length === 0 ? "none" : "select"
      emptyIcon: root.editor.items.length === 0 ? "widgets" : ""
      emptyText: root.editor.items.length === 0 ? I18n.tr("No custom widgets yet") : I18n.tr("Select a custom widget to edit it")
      emptyHint: root.editor.items.length === 0 ? I18n.tr("Add a custom widget on the left: point it at a script, then pick what its output shows on the bar and in its module.") : ""

      pinned: Loader {
        active: root.editor.selected !== null && !root.editor.importing
        visible: active
        Layout.fillWidth: true

        sourceComponent: ColumnLayout {
          spacing: Widget.spacing

          InspectorHeader {
            icon: root.editor.selected?.icon || "widgets"
            title: root.editor.selected?.name || root.editor.selected?.id || ""
            subtitle: root.editor.selected?.command ?? ""
            canDuplicate: true
            canRemove: true
            removeTooltip: I18n.tr("Remove this custom widget")
            onDuplicate: root.editor.duplicate(root.editor.selectedIndex)
            onRemove: root.editor.remove(root.editor.selectedIndex)

            // Copy: the definition on the clipboard, to share by hand
            StyledIconButton {
              iconText: "share"
              tooltipText: I18n.tr("Copy this widget to share")
              onClicked: root.editor.copyDefinition()
            }
          }

          Notice {
            visible: root.editor.copyNote !== ""
            status: "success"
            text: root.editor.copyNote
            actionText: I18n.tr("Dismiss")
            onTriggered: root.editor.copyNote = ""
          }
        }
      }

      // Only the shown tab is built
      KeyedLoader {
        id: tabs
        Layout.fillWidth: true
        Layout.preferredHeight: tabs.childrenRect.height
        key: root.editor.importing ? "import" : root.editor.selected !== null ? root.editor.tab + ":" + root.editor.selectedId : ""
        sourceComponent: root.editor.importing ? importForm : root.editor.tab === 1 ? barTab : root.editor.tab === 2 ? moduleTab : dataTab
      }

      Component {
        id: importForm
        ImportForm {}
      }

      Component {
        id: dataTab
        DataTab {}
      }
      Component {
        id: barTab
        BarTab {
          grid: root.grid
        }
      }
      Component {
        id: moduleTab
        ModuleTab {
          grid: root.grid
          availableHeight: pane.bodyHeight
        }
      }
    }
  }
}
