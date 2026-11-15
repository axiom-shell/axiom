pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.system
import qs.components.reusable

// Custom widgets page, Help tab (also the empty pane's "How custom widgets
// work"): what a script prints and how the definition reads it, mirroring
// docs/dev/features/custom-widgets.md › Script contract. One section open at
// a time (CustomWidgetsEditor.helpSection, which the Data tab's "What should
// my script print?" and the "?" beside the Action combo and each binding
// set): the output, the action command's placeholders, an example script per
// mode, the slots every element has and each kind's, lifetime, failure and
// Waybar notes.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property string section: root.editor.helpSection

  // The output's keys and what each means
  readonly property var contract: [["text, alt, tooltip, class, percentage", I18n.tr("Waybar's: Pango markup in text and tooltip unless the definition escapes it.")], ["icon, value, min, max, unit, subtext, badge, urgent, image, hidden", I18n.tr("axiom's: an icon name, a number and its range, a unit, a second line, a count, a picture, hidden.")], ["items", I18n.tr("Rows: {text, icon, value, subtext, id, state, max, image}. A row's id is what its action receives; state tones it; a value with a max draws a meter; image is a thumbnail.")], ["state", I18n.tr("The script's mode name: screens match it, and the States colour it. A word with no colour, or a hex, colours nothing.")], ["rev", I18n.tr("The screen's revision, passed back to an action as {rev}, so it can refuse a stale screen.")], ["actions", I18n.tr("{id: {enabled}}: an action it doesn't list is off; enabled false, \"false\", 0, no and off turn it off.")], ["error", I18n.tr("Non-empty: the widget is failing, and the Failed screen shows this text.")], [I18n.tr("anything else"), I18n.tr("Data, bound by its path: player.title, items.0.text. A list of numbers draws on a Sparkline.")]]

  // Example scripts: poll, stream and the action command
  readonly property string pollExample: "#!/bin/sh\n# Mode: poll. Prints one JSON object each time it runs.\nload=$(awk '{print int($1 * 100)}' /proc/loadavg)\nprintf '{\"text\": \"load %s\", \"value\": %s, \"max\": 400, \"state\": \"ok\"}\\n' \"$load\" \"$load\"\n"
  readonly property string streamExample: "#!/bin/sh\n# Mode: stream. One JSON line per change, never buffered.\nwhile true; do\n  printf '{\"text\": \"%s\"}\\n' \"$(date +%H:%M:%S)\"\n  sleep 1\ndone\n"
  readonly property string invokeExample: "#!/bin/sh\n# The action command: sh -c 'mylist.sh {action} {value}'.\n# Both arrive already quoted; it should exit quickly.\ncase \"$1\" in\n  add)   echo \"$2\" >> \"$HOME/.local/state/mylist\" ;;\n  clear) : > \"$HOME/.local/state/mylist\" ;;\n  *)     echo \"unknown action $1\" >&2; exit 2 ;;\nesac\n"

  // A section: open while it is the one the editor points at
  component Fold: FoldingSection {
    required property string key
    collapsed: root.section !== key
    onToggled: root.editor.helpSection = root.section === key ? "" : key
  }

  // A script to copy
  component Example: ColumnLayout {
    id: example
    property string title
    property string code
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    RowLayout {
      Layout.fillWidth: true
      StyledLabel {
        Layout.fillWidth: true
        text: example.title
        overflow: "line"
      }
      StyledTextButton {
        implicitHeight: Widget.smallHeight
        iconText: "content_copy"
        text: I18n.tr("Copy")
        onClicked: ClipboardManager.copyText(example.code)
      }
    }
    Surface {
      Layout.fillWidth: true
      tone: "highest"
      implicitHeight: codeText.implicitHeight + Widget.padding * 2

      StyledText {
        id: codeText
        anchors.fill: parent
        anchors.margins: Widget.padding
        text: example.code
        textFamily: "monospace"
        role: "caption"
        overflow: "wrap"
      }
    }
  }

  // A paragraph
  component Para: StyledText {
    Layout.fillWidth: true
    role: "caption"
    tone: "muted"
    overflow: "wrap"
  }

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  Fold {
    key: "output"
    title: I18n.tr("What the script prints")
    description: I18n.tr("Waybar's keys, and axiom's.")

    Para {
      text: I18n.tr("Run it as poll (every interval), stream (one sample a line) or once, and print text (the last line), Waybar's JSON or JSON: one object per run. These keys mean something; anything else is data you bind to.")
    }
    // By count over a fixed list
    Repeater {
      model: root.contract.length

      RowLayout {
        id: row
        required property int index
        readonly property var entry: root.contract[row.index]
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 12
          Layout.alignment: Qt.AlignTop
          text: row.entry[0]
          textFamily: "monospace"
          role: "caption"
          overflow: "wrap"
        }
        Para {
          text: row.entry[1]
        }
      }
    }
  }

  Fold {
    key: "actions"
    title: I18n.tr("Actions and placeholders")
    description: I18n.tr("The action command, and what it is given.")

    Para {
      text: I18n.tr("A button, row, toggle, slider, entry or key names an action; the action command runs it as one sh -c line. {action} is the id and {value} the button's value, a row's id (else value, else text), on or off, the number a slider was released at, or the typed text. {rev} is the current screen's revision; {tree} is this shell's folder. They arrive already quoted (a plain number bare, anything else in single quotes): don't quote them yourself.")
    }
    Para {
      text: I18n.tr("Nothing runs on the lock screen, while the script isn't answering, when the output turns the action off, with no action command, or while another action holds the widget: a double press acts once. axiom:refresh, axiom:restart and the shell's own actions need no command. axiom ipc customWidgets act NAME ACTION runs one from a terminal while the widget is shown.")
    }
    Example {
      title: I18n.tr("An action command")
      code: root.invokeExample
    }
  }

  Fold {
    key: "examples"
    title: I18n.tr("Example scripts")
    description: I18n.tr("Copy one, point the Script's command at it.")

    Example {
      title: I18n.tr("Poll: a number and its state")
      code: root.pollExample
    }
    Example {
      title: I18n.tr("Stream: one line per change")
      code: root.streamExample
    }
  }

  Fold {
    key: "slots"
    title: I18n.tr("Slots")
    description: I18n.tr("What each element can be bound to.")

    Para {
      text: I18n.tr("A slot reads a key (value), a path (player.title), a format ({text}%) or a literal (=Hello). Empty: the output's own key. Every element also has Show when (hidden while false) and Color by (a word the States map to a colour).")
    }
    // By count over the schema's element kinds
    Repeater {
      model: CustomWidgetsConfig.elementKinds.length

      RowLayout {
        id: kindRow
        required property int index
        readonly property var kind: CustomWidgetsConfig.elementKinds[kindRow.index]
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 12
          Layout.alignment: Qt.AlignTop
          text: I18n.tr(kindRow.kind.label)
          role: "caption"
          overflow: "wrap"
        }
        Para {
          text: kindRow.kind.slots.join(", ")
          textFamily: "monospace"
        }
      }
    }
  }

  Fold {
    key: "lifetime"
    title: I18n.tr("When it runs")
    description: I18n.tr("A script runs only while something shows it.")

    Para {
      text: I18n.tr("A script runs while a bar widget, a popout, a module or this page shows its widget, and a stream is stopped when nothing does. Keep a widget's state outside the stream (a file or a daemon): the action command must not need it. An element or bar click always has its widget shown; axiom ipc customWidgets act answers \"not shown\" when nothing shows it. Long jobs should detach and report through the state; the action command exits quickly.")
    }
  }

  Fold {
    key: "failure"
    title: I18n.tr("When it fails")
    description: I18n.tr("Only a widget with an action command or screens can fail.")

    Para {
      text: I18n.tr("It fails when the script can't start, a stream exits with an error, a run exits with an error and no output, or the output has a non-empty error. Add a screen for it (\"When it fails\") or the stock error screen shows the message with Restart. While it fails, named actions are off; the built-in ones still work.")
    }
  }

  Fold {
    key: "waybar"
    title: I18n.tr("Waybar scripts")
    description: I18n.tr("They keep working.")

    Para {
      text: I18n.tr("A Waybar custom module's script runs as it is (Import a widget reads its config). A script that refreshes Waybar with pkill -RTMIN+N waybar should run axiom ipc customWidgets refresh NAME instead. A frame-rate stream such as cava isn't supported: a stream is coalesced to 4 pushes a second.")
    }
  }
}
