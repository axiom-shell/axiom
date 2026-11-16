pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.forms

// One action of the selected custom widget (actions.items[index]), edited in
// an ItemBox that folds: collapsed it is its header (the name, the kind) and
// a one-line summary of what it runs; open, its form rows: its name, Runs (a
// Command | Axiom action toggle beside its label), what it runs (a command,
// or one of the Axiom actions), and, for a command, whether the widget waits
// for it (a switch row). Move and remove buttons are in the header (remove's
// tooltip says how many triggers use it). Used by the Data tab's Actions group and inline under
// a trigger (TriggerField). Name and command are pushed in while unfocused
// and written on each edit.
ItemBox {
  id: root

  required property int index
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var item: root.editor.selected?.actions?.items?.[root.index] ?? null
  readonly property string itemId: root.item?.id ?? ""
  readonly property int uses: root.editor.actionUses(root.itemId)
  // The Axiom action's label, else the value as it stands
  readonly property string axiomLabel: root.editor.axiomChoices.find(c => c.value === root.item?.axiom)?.label ?? root.item?.axiom ?? ""

  // Folded or not: page-only, never written. A just-added action and a row
  // opened inline (TriggerField) start open
  property bool openAtStart: false
  open: root.openAtStart || (root.itemId !== "" && root.editor.focusAction === root.itemId)
  // What the action runs, in a word or two, for the folded line
  summary: root.item?.kind === "axiom" ? root.axiomLabel : (root.item?.command ?? "")

  bodySpacing: 0
  foldable: true
  title: root.item?.name || I18n.tr("Unnamed")
  caption: root.open ? "" : root.item?.kind === "axiom" ? I18n.tr("Axiom action") : I18n.tr("Command")
  removable: true
  removeTooltip: root.uses > 0 ? I18n.tr("Remove (used by {0})", root.uses) : I18n.tr("Remove")
  onToggled: root.open = !root.open
  onRemove: root.editor.removeAction(root.index)

  // A new action takes the focus in its name (the editor's flag, which this
  // row reads once it exists)
  Component.onCompleted: {
    // keep what the binding gave, whatever the flag does next
    root.open = root.open;
    if (root.itemId !== "" && root.editor.focusAction === root.itemId) {
      root.editor.focusAction = "";
      nameEntry.input.forceActiveFocus();
    }
  }

  headerActions: [
    StyledIconButton {
      visible: !root.openAtStart
      size: Widget.compactHeight
      iconText: "arrow_upward"
      tooltipText: I18n.tr("Move up")
      enabled: root.index > 0
      onClicked: root.editor.moveAction(root.index, root.index - 1)
    },
    StyledIconButton {
      visible: !root.openAtStart
      size: Widget.compactHeight
      iconText: "arrow_downward"
      tooltipText: I18n.tr("Move down")
      enabled: root.index < root.editor.selected.actions.items.length - 1
      onClicked: root.editor.moveAction(root.index, root.index + 1)
    }
  ]

  FieldRow {
    label: I18n.tr("Name")

    CommitEntry {
      id: nameEntry
      Layout.fillWidth: true
      live: true
      value: root.item?.name ?? ""
      onEdited: text => root.editor.setAction(root.index, "name", text)
    }
  }

  FormRow {
    activates: kindField
    bodyHeight: kindField.implicitHeight

    SchemaToggle {
      id: kindField
      width: parent.width
      label: I18n.tr("Runs")
      options: ["command", "axiom"]
      optionLabels: ({
          "command": I18n.tr("Command"),
          "axiom": I18n.tr("Axiom action")
        })
      currentValue: root.item?.kind ?? "command"
      onPicked: value => root.editor.setAction(root.index, "kind", value)
    }
  }

  FieldRow {
    shown: root.item?.kind !== "axiom"
    label: I18n.tr("Command")
    description: I18n.tr("{value}: what the element sends. {arg}: the trigger's argument (else added at the end). {rev} and {tree} too. Quoted for you.")
    belowShown: (root.item?.command ?? "") === ""

    CommitEntry {
      Layout.fillWidth: true
      live: true
      value: root.item?.command ?? ""
      placeholderText: I18n.tr("e.g. notify-send hi")
      input.font.family: "monospace"
      onEdited: text => root.editor.setAction(root.index, "command", text)
    }
    below: StyledText {
      Layout.fillWidth: true
      text: I18n.tr("No command yet")
      role: "caption"
      tone: "warning"
    }
  }

  FieldRow {
    shown: root.item?.kind === "axiom"
    label: I18n.tr("Axiom action")
    description: I18n.tr("refresh, restart, screen:<screen id> (screen: the base), or a shell action that takes no argument.")

    StyledComboEntry {
      id: axiomCombo
      Layout.fillWidth: true
      editable: true
      placeholderText: I18n.tr("An Axiom action")
      value: root.axiomLabel
      search: query => {
        const q = query.trim().toLowerCase();
        return root.editor.axiomChoices.filter(c => q === "" || c.label.toLowerCase().includes(q));
      }
      // Only a listed action commits; anything else typed shows the value again
      onPicked: value => {
        if (root.editor.axiomChoices.some(c => c.value === value))
          root.editor.setAction(root.index, "axiom", value);
        axiomCombo.showValue();
      }
    }
  }

  SwitchRow {
    shown: root.item?.kind !== "axiom"
    label: I18n.tr("Wait for it to finish")
    description: I18n.tr("Other actions wait, and a failure shows on the button. Off for commands that open an app.")
    checked: root.item?.wait ?? true
    onToggled: value => root.editor.setAction(root.index, "wait", value)
  }

  StyledText {
    visible: root.uses > 0
    Layout.fillWidth: true
    Layout.topMargin: Style.space2
    Layout.bottomMargin: Style.rowPadding
    text: I18n.tr("Used by {0}", root.uses)
    role: "caption"
    tone: "faint"
  }
}
