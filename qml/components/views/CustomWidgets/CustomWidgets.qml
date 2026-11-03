pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.views.base

// The Custom widgets page (docs/dev/features/custom-widgets.md): the
// definitions and the selected one's script on the left; on the right its
// data (the script's output, and which part of it each field reads), its
// bar look and its module, each a tab. Edits go through
// CustomWidgetsManager.editor's draft and show live on the bars and pages.
BaseView {
  id: root

  readonly property var editor: CustomWidgetsManager.editor

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

    TitledCard {
      anchors.fill: parent
      title: root.editor.selected?.name ?? I18n.tr("Custom widgets")
      scrollKey: "CustomWidgets/" + root.editor.tab
      dirty: root.editor.isDirty
      onSave: root.editor.save()
      onReset: root.editor.reset()

      headerExtras: StyledTabBar {
        Layout.fillWidth: true
        visible: root.editor.selected !== null
        tabs: [I18n.tr("Data"), I18n.tr("Bar"), I18n.tr("Module")]
        currentIndex: root.editor.tab
        onTabClicked: index => root.editor.selectTab(index)
      }

      EmptyStateLine {
        visible: root.editor.selected === null
      }

      // Only the shown tab is built
      KeyedLoader {
        id: tabs
        Layout.fillWidth: true
        Layout.preferredHeight: tabs.childrenRect.height
        key: root.editor.selected !== null ? root.editor.tab + ":" + root.editor.selectedId : ""
        sourceComponent: root.editor.tab === 1 ? barTab : root.editor.tab === 2 ? moduleTab : dataTab
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
          availableHeight: root.pageHeight - Widget.height * 4
        }
      }
    }
  }

  component EmptyStateLine: StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Add a custom widget on the left: point it at a script, then pick what its output shows on the bar and in its module.")
    wrapMode: Text.WordWrap
    opacity: 0.7
  }
}
