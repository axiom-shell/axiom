pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.forms
import qs.components.reusable

// The Keybinds editor's inspector for the selected bind
// (KeybindManager.editor.selectedIndex): its key, action, argument and label,
// its flags in words, its issues, and Duplicate, Pause and Remove. Built
// anew for each selection, so typed text never lands on another bind.
ColumnLayout {
  id: root

  // The bind it edits, fixed while it lives (a new selection rebuilds it)
  required property int bindIndex
  readonly property var bind: KeybindManager.editor.binds[root.bindIndex] ?? ({})
  readonly property var issues: KeybindManager.editor.issues[root.bindIndex] ?? []
  readonly property bool hasError: root.issues.some(issue => issue.level === "error")
  readonly property bool paused: root.bind.paused === true
  readonly property bool needed: KeybindManager.needsArgument(root.bind.action)
  readonly property var callOptions: KeybindManager.callOptions(root.bind.action)
  readonly property var argumentOptions: {
    const options = KeybindManager.argumentOptions(root.bind.action);
    const current = root.bind.argument ?? "";
    return options && current !== "" && !options.includes(current) ? [current].concat(options) : options;
  }

  spacing: Widget.spacing * 2

  // Text fields keep what's being typed; otherwise they follow the bind.
  // They commit as editing finishes, focus loss included, only once typed in.
  onBindChanged: {
    if (!argumentText.typed)
      argumentText.input.text = root.bind.argument ?? "";
    if (!label.typed)
      label.input.text = root.bind.description ?? "";
  }

  InspectorHeader {
    icon: KeybindManager.actionIcon(root.bind.action)
    filled: !root.paused
    title: KeybindManager.displayCombo(root.bind.key) || I18n.tr("No key yet")
    subtitle: (KeybindManager.actionLabels[root.bind.action] ?? "") + (root.paused ? "  ·  " + I18n.tr("Paused") : "")

    SquareIconButton {
      size: Widget.height
      iconText: "content_copy"
      tooltipText: I18n.tr("Duplicate, then record its key")
      onClicked: KeybindManager.editor.duplicateBind(root.bindIndex)
    }

    SquareIconButton {
      size: Widget.height
      iconText: root.paused ? "play_arrow" : "pause"
      tooltipText: root.paused ? I18n.tr("Resume") : I18n.tr("Pause: keep it, but don't bind it")
      onClicked: KeybindManager.editor.setPaused([root.bindIndex], !root.paused)
    }

    SquareIconButton {
      visible: KeybindManager.editor.changedBinds[root.bindIndex] === true
      size: Widget.height
      iconText: "history"
      tooltipText: I18n.tr("Revert to the saved bind")
      onClicked: KeybindManager.editor.revertBind(root.bindIndex)
    }

    SquareIconButton {
      size: Widget.height
      iconText: "delete"
      tooltipText: I18n.tr("Remove")
      hoverColor: Theme.error
      onClicked: KeybindManager.editor.removeBind(root.bindIndex)
    }

    SquareIconButton {
      size: Widget.height
      iconText: "close"
      tooltipText: I18n.tr("Close, to see the key map")
      onClicked: KeybindManager.editor.selectBind(-1)
    }
  }

  FieldGroup {
    title: I18n.tr("Key")

    KeyRecorder {
      bindIndex: root.bindIndex
      combo: root.bind.key ?? ""
      invalid: root.hasError
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Click, then press the combo. A scroll records a wheel bind; a modifier tapped alone records a tap.")
      opacity: 0.6
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }

  FieldGroup {
    title: I18n.tr("Action")

    ActionPicker {
      currentValue: root.bind.action ?? ""
      onPicked: action => KeybindManager.editor.setField(root.bindIndex, "action", action)
      Layout.fillWidth: true
    }

    // The argument: a choice when the action has a fixed set, else text
    SchemaComboBox {
      visible: root.needed && root.argumentOptions !== null
      label: ""
      options: root.argumentOptions ?? []
      currentValue: root.bind.argument ?? ""
      // I18n.tr("left") I18n.tr("right") I18n.tr("up") I18n.tr("down")
      // I18n.tr("region") I18n.tr("window") I18n.tr("screen")
      onSelectionChanged: value => KeybindManager.editor.setField(root.bindIndex, "argument", value)
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
    }

    StyledTextEntry {
      id: argumentText
      visible: root.needed && root.argumentOptions === null
      placeholderText: {
        switch (KeybindManager.argumentKind(root.bind.action)) {
        case "resize":
          return I18n.tr("Step, e.g. 50 0");
        case "special":
          return I18n.tr("Workspace name");
        case "raw":
          return {
            "sway": I18n.tr("Command, e.g. splitv"),
            "niri": I18n.tr("Action, e.g. focus-column-first")
          }[root.bind.compositor] ?? I18n.tr("Dispatcher, e.g. hl.dsp.layout(\"swapsplit\")");
        }
        return root.bind.action === "exec" ? I18n.tr("Command") : I18n.tr("Search text");
      }
      Component.onCompleted: input.text = root.bind.argument ?? ""
      input.onEditingFinished: {
        if (argumentText.typed)
          KeybindManager.editor.setField(root.bindIndex, "argument", input.text);
        argumentText.typed = false;
      }
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
    }

    // The call: toggle, open or close
    SchemaComboBox {
      visible: root.callOptions !== null
      // I18n.tr("Does")
      label: "Does"
      options: root.callOptions ?? []
      optionLabels: KeybindManager.callLabels(root.bind.action)
      currentValue: root.bind.call ?? "toggle"
      onSelectionChanged: value => KeybindManager.editor.setField(root.bindIndex, "call", value)
      Layout.fillWidth: true
    }
  }

  FieldGroup {
    title: I18n.tr("Label")

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      // The section the action files it under, unless the label names its
      // own ("Section: Label")
      StyledText {
        visible: !BindActions.hasOwnSection(label.input.text)
        text: I18n.tr(BindActions.sectionFor(KeybindManager.actionTable, root.bind.action)) + "  ›"
        opacity: 0.5
        textSize: Appearance.fontSizeBy(-1)
      }

      StyledTextEntry {
        id: label
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        placeholderText: BindActions.defaultLabel(KeybindManager.actionTable, root.bind) || I18n.tr("Label")
        Component.onCompleted: input.text = root.bind.description ?? ""
        input.onEditingFinished: {
          if (label.typed)
            KeybindManager.editor.setField(root.bindIndex, "description", input.text);
          label.typed = false;
        }
      }
    }

    StyledText {
      text: I18n.tr("Empty uses the action's name. \"Section: Label\" files it under a section of its own.")
      opacity: 0.6
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }

  FieldGroup {
    title: I18n.tr("When it fires")

    Repeater {
      model: [["repeating", I18n.tr("Repeat while held"), I18n.tr("Fires again and again while the key stays down, as volume keys do.")], ["locked", I18n.tr("Works while locked"), I18n.tr("Also fires on the lock screen.")], ["release", I18n.tr("Fire on release"), I18n.tr("Fires when the key is let go rather than pressed.")]]

      delegate: RowLayout {
        id: flag
        required property var modelData
        readonly property bool on: root.bind[flag.modelData[0]] === true
        Layout.fillWidth: true
        spacing: Widget.spacing

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            text: flag.modelData[1]
            Layout.fillWidth: true
          }

          StyledText {
            text: flag.modelData[2]
            opacity: 0.6
            textSize: Appearance.fontSizeBy(-2)
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        StyledSwitch {
          checkable: false
          checked: flag.on
          onClicked: KeybindManager.editor.setField(root.bindIndex, flag.modelData[0], !flag.on)
        }
      }
    }
  }

  IssueList {
    visible: root.issues.length > 0
    issues: root.issues
    textSize: Appearance.fontSizeBy(-1)
    Layout.fillWidth: true
  }
}
