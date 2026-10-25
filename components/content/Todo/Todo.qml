pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The todo list (TodoManager): the Todo widget's popout, or an overlay
// card. A header with the open count and Clear completed, then the list
// (TodoList). Compact, the open count.
// properties (card): { showHeader }
Panel {
  id: root

  readonly property int doneCount: TodoManager.items.length - TodoManager.openCount

  spacing: Widget.spacing
  wantsKeyboardFocus: true
  implicitWidth: Math.max(Appearance.fontSize * 22, body.implicitWidth + margins * 2)
  maxImplicitHeight: Appearance.fontSize * 32
  fullMinWidth: Appearance.fontSize * 12
  fullMinHeight: Appearance.fontSize * 8

  compactContent: CompactFigure {
    icon: "checklist"
    value: String(TodoManager.openCount)
    label: I18n.tr("to do")
  }

  ModuleHeader {
    visible: !root.embedded || (root.properties.showHeader ?? true)
    icon: "checklist"
    title: TodoManager.openCount > 0 ? I18n.tr("{0} to do", TodoManager.openCount) : I18n.tr("Todo")

    FlatIconButton {
      visible: root.doneCount > 0
      size: Math.round(Appearance.fontSize * 1.8)
      iconText: "clear_all"
      tooltipText: I18n.tr("Clear completed")
      onClicked: TodoManager.clearCompleted()
    }
  }

  TodoList {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    fill: root.embedded
    maxListHeight: Appearance.fontSize * 24
  }
}
