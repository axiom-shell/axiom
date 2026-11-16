pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.forms

// One action of the selected custom widget (actions.items[index]), edited in
// a box that folds: collapsed it is one line (the name, the kind and a short
// summary of what it runs); open, its form rows: its name and a remove
// button, Runs (a Command | Axiom action toggle beside its label), what it
// runs (a command, or one of the Axiom actions), and, for a command, whether
// the widget waits for it (a switch row). Used by the Data tab's Actions group and inline under
// a trigger (TriggerField). Name and command are pushed in while unfocused
// and written on textEdited.
Surface {
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
  property bool open: root.openAtStart || (root.itemId !== "" && root.editor.focusAction === root.itemId)
  // What the action runs, in a word or two, for the folded line
  readonly property string summary: root.item?.kind === "axiom" ? root.axiomLabel : (root.item?.command ?? "")

  Layout.fillWidth: true
  tone: "sunken"
  outlined: true
  implicitHeight: rows.implicitHeight + (root.open ? Style.space3 : Widget.smallPadding) * 2
  clip: true

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

  // The whole folded box hovers and opens, not only its line
  StateLayer {
    hovered: !root.open && (foldArea.containsMouse || head.hovered)
    radius: root.radius
  }

  MouseArea {
    id: foldArea
    anchors.fill: parent
    enabled: !root.open
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open = true
  }

  ColumnLayout {
    id: rows
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space3
    anchors.rightMargin: Style.space3
    anchors.topMargin: root.open ? Style.space3 : Widget.smallPadding
    spacing: 0

    FoldRow {
      id: head
      open: root.open
      tinted: root.open
      Layout.topMargin: root.open ? Style.rowPadding : 0
      Layout.bottomMargin: root.open ? Style.rowPadding : 0
      onToggled: root.open = !root.open

      StyledText {
        text: root.item?.name || I18n.tr("Unnamed")
        role: "label"
        overflow: "line"
        Layout.maximumWidth: head.width / 2
      }
      StyledText {
        visible: !root.open
        text: root.item?.kind === "axiom" ? I18n.tr("Axiom action") : I18n.tr("Command")
        role: "caption"
        tone: "muted"
      }
      StyledText {
        visible: !root.open
        Layout.fillWidth: true
        text: root.summary
        role: "caption"
        tone: root.summary === "" ? "warning" : "faint"
        overflow: "line"
      }
      Item {
        visible: root.open
        Layout.fillWidth: true
      }
    }

    FoldingColumn {
      id: body
      open: root.open
      Layout.fillWidth: true

      InspectorRow {
        first: true
        label: I18n.tr("Name")

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledTextEntry {
            id: nameEntry
            Layout.fillWidth: true
            onTextEdited: root.editor.setAction(root.index, "name", nameEntry.text)

            Binding {
              target: nameEntry
              property: "text"
              value: root.item?.name ?? ""
              when: !nameEntry.input.activeFocus
              restoreMode: Binding.RestoreNone
            }
          }
          StyledIconButton {
            visible: !root.openAtStart
            iconText: "arrow_upward"
            tooltipText: I18n.tr("Move up")
            enabled: root.index > 0
            onClicked: root.editor.moveAction(root.index, root.index - 1)
          }
          StyledIconButton {
            visible: !root.openAtStart
            iconText: "arrow_downward"
            tooltipText: I18n.tr("Move down")
            enabled: root.index < root.editor.selected.actions.items.length - 1
            onClicked: root.editor.moveAction(root.index, root.index + 1)
          }
          StyledIconButton {
            iconText: "delete"
            kind: "danger"
            tooltipText: root.uses > 0 ? I18n.tr("Remove (used by {0})", root.uses) : I18n.tr("Remove")
            onClicked: root.editor.removeAction(root.index)
          }
        }
      }

      FormRow {
        hoverable: true
        bodyHeight: kindField.implicitHeight
        onRowClicked: kindField.activate()

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

      InspectorRow {
        shown: root.item?.kind !== "axiom"
        label: I18n.tr("Command")
        description: I18n.tr("{value}: what the element sends. {arg}: the trigger's argument (else added at the end). {rev} and {tree} too. Quoted for you.")
        belowShown: (root.item?.command ?? "") === ""

        StyledTextEntry {
          id: commandEntry
          Layout.fillWidth: true
          placeholderText: I18n.tr("e.g. notify-send hi")
          input.font.family: "monospace"
          onTextEdited: root.editor.setAction(root.index, "command", commandEntry.text)

          Binding {
            target: commandEntry
            property: "text"
            value: root.item?.command ?? ""
            when: !commandEntry.input.activeFocus
            restoreMode: Binding.RestoreNone
          }
        }
        below: StyledText {
          Layout.fillWidth: true
          text: I18n.tr("No command yet")
          role: "caption"
          tone: "warning"
        }
      }

      InspectorRow {
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

      FormRow {
        shown: root.item?.kind !== "axiom"
        hoverable: true
        bodyHeight: waitField.implicitHeight
        onRowClicked: waitField.activate()

        SchemaSwitch {
          id: waitField
          width: parent.width
          label: I18n.tr("Wait for it to finish")
          description: I18n.tr("Other actions wait, and a failure shows on the button. Off for commands that open an app.")
          checked: root.item?.wait ?? true
          onToggled: value => root.editor.setAction(root.index, "wait", value)
        }
      }

      StyledText {
        visible: root.uses > 0
        Layout.fillWidth: true
        Layout.bottomMargin: Style.rowPadding
        text: I18n.tr("Used by {0}", root.uses)
        role: "caption"
        tone: "faint"
      }
    }
  }
}
