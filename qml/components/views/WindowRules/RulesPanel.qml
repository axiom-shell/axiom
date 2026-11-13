pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.views.Layouts

// Window rules page, left: the rules in priority order (dragged to
// reorder, switched on and off, copied, removed), and New rule.
Item {
  id: root

  readonly property var editor: WindowRulesManager.editor

  TitledCard {
    anchors.fill: parent
    title: I18n.tr("Your rules")
    scrollKey: "WindowRules/list"
    showActions: false

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Drag to order: when two rules set the same thing, the higher one wins.")
      wrapMode: Text.WordWrap
      textSize: Appearance.fontSizeBy(-2)
      opacity: 0.7
    }

    // Carries the rows
    InlineDragLayer {
      id: carrier
      accepts: (target, drag) => target.takes(drag)
      onDropped: (drag, target, index) => target.dropRequested(drag, index)
    }

    EntryListTarget {
      id: ruleList
      dragLayer: carrier
      moveKind: "window-rule-move"
      count: root.editor.rules.length
      onDropRequested: (drag, index) => root.editor.move(drag.index, index)

      Repeater {
        model: ruleList.count

        EntryListRow {
          id: ruleRow
          readonly property var item: root.editor.rules[ruleRow.index] ?? ({})
          readonly property int problems: WindowRuleIssues.of(root.editor.report, ruleRow.item.id).length

          list: ruleList
          icon: ruleRow.item.icon || "select_window"
          label: ruleRow.item.name || ruleRow.item.id || ""
          selected: root.editor.selectedIndex === ruleRow.index
          dimmed: ruleRow.item.enabled === false
          changed: root.editor.changed(ruleRow.index)
          onClicked: root.editor.select(ruleRow.index)

          badges: [
            StyledText {
              // How many open windows its conditions match now, on or off
              readonly property int open: root.editor.openCount(ruleRow.index)
              visible: open > 0
              text: I18n.tr("{0} open", open)
              textColor: ruleRow.ink
              opacity: 0.6
              textSize: Appearance.fontSizeBy(-1)
            },
            IssueIcon {
              visible: ruleRow.problems > 0
              level: "error"
              textSize: Appearance.fontSizeBy(-1)
              tip: I18n.tr("{0} problems", ruleRow.problems)
            }
          ]

          RowAction {
            row: ruleRow
            iconText: ruleRow.item.enabled === false ? "toggle_off" : "toggle_on"
            lit: ruleRow.item.enabled !== false
            tooltipText: ruleRow.item.enabled === false ? I18n.tr("Turn on") : I18n.tr("Turn off")
            onClicked: root.editor.setEnabled(ruleRow.index, ruleRow.item.enabled === false)
          }
          RowAction {
            row: ruleRow
            iconText: "content_copy"
            tooltipText: I18n.tr("Copy this rule")
            onClicked: root.editor.duplicate(ruleRow.index)
          }
          RowAction {
            row: ruleRow
            danger: true
            iconText: "close"
            tooltipText: I18n.tr("Remove this rule")
            onClicked: root.editor.remove(ruleRow.index)
          }
        }
      }
    }

    StyledText {
      visible: root.editor.rules.length === 0
      Layout.fillWidth: true
      text: I18n.tr("No rules yet.")
      textColor: Theme.foregroundAlt
      wrapMode: Text.WordWrap
    }

    AddEntryButton {
      Layout.topMargin: Widget.spacing
      Layout.fillWidth: true
      text: I18n.tr("New rule")
      onClicked: root.editor.add()
    }

    // Applies the saved rules, so it waits for the draft to be saved. The
    // button stays hoverable while it waits, to say why
    StyledTextButton {
      readonly property bool ready: WindowRulesManager.state?.running === true && !root.editor.isDirty

      Layout.fillWidth: true
      implicitHeight: Widget.height
      opacity: ready ? 1 : 0.5
      iconText: "select_window"
      text: I18n.tr("Apply to open windows")
      tooltipText: root.editor.isDirty ? I18n.tr("Save your changes first.") : I18n.tr("Moves the open windows as your saved rules say.")
      onClicked: {
        if (ready)
          WindowRulesManager.applyNow();
      }
    }
  }
}
