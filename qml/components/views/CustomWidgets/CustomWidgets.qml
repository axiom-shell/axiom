pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.forms
import qs.components.views.base

// The Custom widgets page (docs/dev/features/custom-widgets.md): the
// definitions on the left; on the right its data (the script, its output,
// and which part of it each field reads), its
// bar look, its module and Help, each a tab (or, while adding, the Import
// form or the template gallery). Edits go through
// CustomWidgetsManager.editor's draft and show live on the bars and pages.
BaseView {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property var tabNames: [I18n.tr("Data"), I18n.tr("Bar"), I18n.tr("Module"), I18n.tr("Help")]

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
      // Undo/Redo for every tab: the one history is the definition's
      headerTools: UndoRedoButtons {
        visible: root.editor.selected !== null && !root.editor.formOpen
        canUndo: root.editor.elements.canUndo
        canRedo: root.editor.elements.canRedo
        onUndo: root.editor.elements.undo()
        onRedo: root.editor.elements.redo()
      }
      tabMarked: root.editor.changedTabs

      tabModel: (root.editor.selected !== null || root.editor.tab === 3) && !root.editor.formOpen ? root.tabNames : []
      tabIndex: root.editor.tab
      onTabClicked: index => root.editor.selectTab(index)

      emptyKind: root.editor.selected !== null || root.editor.formOpen || root.editor.tab === 3 ? "" : root.editor.items.length === 0 ? "none" : "select"
      emptyIcon: root.editor.items.length === 0 ? "widgets" : ""
      emptyText: root.editor.items.length === 0 ? I18n.tr("No custom widgets yet") : I18n.tr("Select a custom widget to edit it")
      emptyActionText: I18n.tr("How custom widgets work")
      onEmptyTriggered: root.editor.openHelp("output")
      emptyHint: root.editor.items.length === 0 ? I18n.tr("Add a custom widget on the left: point it at a script, then pick what its output shows on the bar and in its module.") : ""

      pinned: Loader {
        active: root.editor.selected !== null && !root.editor.formOpen
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
            // Where to put it: hints only (nothing here writes a bar or a page);
            // hidden while unsaved, so no bar or page names an unsaved id
            showsLinks: !root.editor.isDirty
            links: [
              SettingsLink {
                page: "BarEditor"
                text: I18n.tr("Put it on a bar")
                icon: "toolbar"
              },
              SettingsLink {
                page: "Layouts"
                text: I18n.tr("Put it on a page")
                icon: "dashboard"
              }
            ]

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

      // Only the shown tab is built; inset, so its rows' hover isn't cut
      // square at the pane's edge
      FormInset {
        KeyedLoader {
          id: tabs
          Layout.fillWidth: true
          Layout.preferredHeight: tabs.childrenRect.height
          key: root.editor.importing ? "import" : root.editor.gallery ? "gallery" : root.editor.tab === 3 ? "help" : root.editor.selected !== null ? root.editor.tab + ":" + root.editor.selectedId : ""
          sourceComponent: root.editor.importing ? importForm : root.editor.gallery ? galleryForm : root.editor.tab === 3 ? helpTab : root.editor.tab === 1 ? barTab : root.editor.tab === 2 ? moduleTab : dataTab
        }
      }

      Component {
        id: helpTab
        CustomWidgetsHelp {}
      }
      Component {
        id: galleryForm
        GalleryForm {}
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
          inspectorWidth: root.inspectorWidth
        }
      }
    }
  }
}
