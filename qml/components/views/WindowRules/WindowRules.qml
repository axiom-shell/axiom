pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.content.base
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

    TitledCard {
      anchors.fill: parent
      title: root.editor.selected ? (root.editor.selected.name || root.editor.selected.id) : I18n.tr("Window rules")
      scrollKey: "WindowRules/" + root.editor.selectedId
      dirty: root.editor.isDirty
      onSave: root.editor.save()
      onReset: root.editor.reset()

      StyledText {
        visible: root.editor.selected === null
        Layout.fillWidth: true
        text: I18n.tr("Add a rule on the left: pick which windows it's for, then what happens when one opens.")
        wrapMode: Text.WordWrap
        opacity: 0.7
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
