pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.system
import qs.components.reusable

// Custom widgets page, Help tab (also the empty pane's "How custom widgets
// work"): a guide per task (show output on the bar, a button, colours, a list,
// screens, placing, sharing), then the reference: what a script prints and
// how the definition reads it, mirroring docs/dev/features/custom-widgets.md
// › Script contract. One section open at a time
// (CustomWidgetsEditor.helpSection, which the Data tab's "What should my
// script print?" and an inspector's "More in Help" set): the output, text
// fields and {paths}, actions and placeholders, example scripts, lifetime,
// failure and Waybar notes.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  readonly property string section: root.editor.helpSection

  // The output's keys and what each means
  readonly property var contract: [["text, alt, tooltip, class, percentage", I18n.tr("Waybar's: Pango markup in text and tooltip unless the definition escapes it.")], ["icon, value, min, max, unit, subtext, badge, urgent, image, hidden", I18n.tr("axiom's: an icon name, a number and its range, a unit, a second line, a count, a picture, hidden.")], ["items", I18n.tr("Rows: {text, icon, value, subtext, id, state, max, image}. A row's id is what its action receives; state tones it; a value with a max draws a meter; image is a thumbnail.")], ["state", I18n.tr("The script's mode name: screens match it, and a Color by state rule can read it. Waybar's words (ok, warning, critical…) and theme colour names colour on their own; any other word colours nothing without a rule.")], ["rev", I18n.tr("The screen's revision, passed back to an action as {rev}, so it can refuse a stale screen.")], ["actions", I18n.tr("{id: {enabled}}: an action it doesn't list is off; enabled false, \"false\", 0, no and off turn it off.")], ["error", I18n.tr("Non-empty: the widget is failing, and a screen on the key error (or the stock error screen) shows this text.")], [I18n.tr("anything else"), I18n.tr("Data, bound by its path: player.title, items.0.text. A list of numbers draws on a Sparkline.")]]

  // Example scripts: poll, stream and the action command
  readonly property string pollExample: "#!/bin/sh\n# Mode: poll. Prints one JSON object each time it runs.\nload=$(awk '{print int($1 * 100)}' /proc/loadavg)\nprintf '{\"text\": \"load %s\", \"value\": %s, \"max\": 400, \"state\": \"ok\"}\\n' \"$load\" \"$load\"\n"
  readonly property string streamExample: "#!/bin/sh\n# Mode: stream. One JSON line per change, never buffered.\nwhile true; do\n  printf '{\"text\": \"%s\"}\\n' \"$(date +%H:%M:%S)\"\n  sleep 1\ndone\n"
  readonly property string actionExample: "#!/bin/sh\n# An action's command: sh -c 'mylist.sh add {value}'.\n# {value} arrives already quoted; it should exit quickly.\necho \"$1\" >> \"$HOME/.local/state/mylist\"\n"

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

  // A task guide: numbered steps, one per line
  component Steps: ColumnLayout {
    id: steps
    property var lines: []
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    // By count over the fixed list of a guide
    Repeater {
      model: steps.lines.length

      Para {
        required property int index
        text: (index + 1) + ". " + steps.lines[index]
      }
    }
  }

  Fold {
    key: "task-bar"
    title: I18n.tr("Show a command's output on the bar")
    description: I18n.tr("The shortest way to a working widget.")

    Steps {
      lines: [I18n.tr("Click New and pick Bar text from a script."), I18n.tr("On the Data tab, type the command in Command (a script that prints some text)."), I18n.tr("Press Run now: what it printed shows under Last output."), I18n.tr("Open the Bar tab to choose the style, the icon and the colour."), I18n.tr("Save, then put it on a bar from the link in the header.")]
    }
  }

  Fold {
    key: "task-button"
    title: I18n.tr("Add a button that runs a command")
    description: I18n.tr("A button on the module, a command behind it.")

    Steps {
      lines: [I18n.tr("Open the Module tab and drag a Button from the library onto the canvas."), I18n.tr("Select it. In Runs, open On press and choose New action…."), I18n.tr("Type the command to run, and name the action."), I18n.tr("Leave Wait for it to finish on, unless the command opens an app."), I18n.tr("Turn on Test actions above the previews to press it for real.")]
    }
  }

  Fold {
    key: "task-color"
    title: I18n.tr("Color text by a value")
    description: I18n.tr("Red above a limit, green below it.")

    Steps {
      lines: [I18n.tr("Select the Text on the Module tab."), I18n.tr("In Colors, pick By state… in the color's list."), I18n.tr("Pick the Key the script prints (a number or a word)."), I18n.tr("Add rules, such as is above 80 → Error and is below 80 → Success.")]
    }
  }

  Fold {
    key: "task-list"
    title: I18n.tr("Show a list")
    description: I18n.tr("Rows from the script's items.")

    Steps {
      lines: [I18n.tr("Make the script print {\"items\": [{\"text\": \"one\"}, {\"text\": \"two\"}]} or a JSON array."), I18n.tr("Drag a List onto the Module tab."), I18n.tr("In Look, set Row text to {name} to show another key of each row."), I18n.tr("To act on a row, give On press an action: it receives the row's id.")]
    }
  }

  Fold {
    key: "task-screens"
    title: I18n.tr("Switch screens with a button")
    description: I18n.tr("A second screen, shown on a press.")

    Steps {
      lines: [I18n.tr("On the Module tab press + beside Base to add a screen."), I18n.tr("Open the Data tab and add an action of the kind Go to screen, with that screen."), I18n.tr("Select a Button on the base and pick the action in On press."), I18n.tr("On the screen, add a Button whose action is Go to screen: Base, to come back.")]
    }
  }

  Fold {
    key: "task-place"
    title: I18n.tr("Put it on a bar or a page")
    description: I18n.tr("Where the widget shows.")

    Steps {
      lines: [I18n.tr("Save, then use the links in the page header: Put it on a bar and Put it on a page."), I18n.tr("In the Bars editor or the Layouts editor, open the library and look under Custom."), I18n.tr("Drag your widget in, then save.")]
    }
  }

  Fold {
    key: "task-share"
    title: I18n.tr("Share a widget")
    description: I18n.tr("One copy, one paste.")

    Steps {
      lines: [I18n.tr("Press Copy beside the widget's name: it goes on the clipboard."), I18n.tr("Send it. The other person opens New, then Import a widget…, pastes and presses Check."), I18n.tr("Files the command uses are not copied: send them too.")]
    }
  }

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
    description: I18n.tr("What an action runs, and what it is given.")

    Para {
      text: I18n.tr("An action is a command (one sh -c line) or an axiom action, listed on the Data tab. A button, row, toggle, slider, entry or bar click picks one by name. {value} is a row's id (else value, else text), on or off, the number a slider was released at, or the typed text; a button or a bar click has none, so its {value} is its Argument. Under the action you pick, Argument adds words to the command (at the end, or where it says {arg}), so one action can serve many buttons; each word is quoted, and a {path} in it is filled from the output. {rev} is the current screen's revision; {tree} is this shell's folder. They arrive already quoted (a plain number bare, anything else in single quotes): don't quote them yourself.")
    }
    Para {
      text: I18n.tr("Nothing runs on the lock screen, while the script isn't answering, when the output turns the action off, with no command, or while another action holds the widget: a double press acts once. Refresh, Restart and the shell's own actions need no command. axiom ipc customWidgets act NAME ACTION runs one from a terminal while the widget is shown.")
    }
    Example {
      title: I18n.tr("An action that adds a line to a file")
      code: root.actionExample
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
    key: "text"
    title: I18n.tr("Text fields and {paths}")
    description: I18n.tr("Typed text is literal; braces read the output.")

    Para {
      text: I18n.tr("What you type in a field (Shows) is shown as typed: Hello shows Hello. {path} reads the output: {text}, {player.title}, {items.0.text}. A field holding only one {path} gets the value itself (a number, a list); text around it, such as {value}% or {title} by {artist}, is filled in as one line. A {path} the output doesn't have stays as typed, and the editor warns about it. Empty: the output's own key for that field. Every element also has Visible (hidden while a test fails) and colours (Color by state). An element that runs actions also has Enabled: its actions do not run, and a Button dims or hides, while its test fails (is on and is off read a value as on or off: false, 0, no and off are off).")
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
      text: I18n.tr("It fails when the script can't start, a stream exits with an error, a run exits with an error and no output, or the output has a non-empty error. Add a screen whose key is error, or the stock error screen shows the message with Restart. When the script can't answer, its command actions are off; an error the script prints itself leaves them to its actions output, so a Fix it button keeps working. Refresh and Restart always work.")
    }
  }

  Fold {
    key: "waybar"
    title: I18n.tr("Waybar scripts")
    description: I18n.tr("They keep working.")

    Para {
      text: I18n.tr("A Waybar custom module's script runs as it is (New › Import a widget reads its config). A script that refreshes Waybar with pkill -RTMIN+N waybar should run axiom ipc customWidgets refresh NAME instead. A frame-rate stream such as cava isn't supported: a stream is coalesced to 4 pushes a second.")
    }
  }
}
