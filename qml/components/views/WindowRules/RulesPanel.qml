pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts
import qs.components.views.base
import qs.components.views.Layouts

// Window rules page, left: the rules in priority order (dragged to reorder,
// switched on and off, copied, removed) and New rule, then the built-in
// switches in a section closed until opened; Apply to open windows stays under
// them.
Item {
  id: root

  readonly property var editor: WindowRulesManager.editor
  // The built-in switches that are on
  readonly property int switchesOn: Object.values(root.editor.switches).filter(value => value === true || value?.enabled === true).length
  // Whether the built-ins section is open (the panel remembers it)
  property bool builtinsOpen: false

  ToolPane {
    anchors.fill: parent
    title: I18n.tr("Window rules")
    headerIcon: "select_window"
    scrollKey: "WindowRules/list"
    showActions: false

    ListSection {
      title: I18n.tr("Your rules")
      count: root.editor.rules.length
      hint: I18n.tr("Drag to order: when two rules set the same thing, the higher one wins.")

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
            issue: ruleRow.problems > 0 ? "error" : ""
            issueTip: I18n.tr("{0} problems", ruleRow.problems)
            onClicked: root.editor.select(ruleRow.index)
            onRemoveRequested: root.editor.remove(ruleRow.index)

            badges: [
              StyledText {
                // How many open windows its conditions match now, on or off
                readonly property int open: root.editor.openCount(ruleRow.index)
                visible: open > 0
                text: I18n.tr("{0} open", open)
                role: "caption"
                textColor: ruleRow.selected ? Style.inkAccentContainer.muted : Style.textMuted
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

      EmptyState {
        visible: root.editor.rules.length === 0
        Layout.alignment: Qt.AlignHCenter
        icon: "select_window"
        text: I18n.tr("No rules yet.")
      }

      AddEntryButton {
        Layout.topMargin: Widget.spacing
        Layout.fillWidth: true
        text: I18n.tr("New rule")
        onClicked: root.editor.add()
      }
    }

    ListSection {
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Built-in rules")
      count: root.switchesOn
      collapsible: true
      open: root.builtinsOpen
      onToggled: root.builtinsOpen = !root.builtinsOpen

      SwitchesGroup {
        Layout.fillWidth: true
      }
    }

    // Applies the saved rules, so it waits for the draft to be saved. The
    // button stays hoverable while it waits, to say why
    footer: StyledTextButton {
      readonly property bool ready: WindowRulesManager.state?.running === true && !root.editor.isDirty

      Layout.fillWidth: true
      implicitHeight: Widget.height
      opacity: ready ? 1 : Style.opacityDisabled
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
