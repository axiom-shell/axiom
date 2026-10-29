pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.services.apps
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions, type labels)
ColumnLayout {
  id: root
  required property string label
  required property string currentConfigValue
  property string description: ""
  // After the label (FieldHeader.trailing)
  property Component headerExtra: null
  property var pattern: null
  // Lines of its own (`x-multiline`), e.g. a system prompt: Enter makes a
  // new one. Otherwise the value is one line, wrapped to show it whole
  property bool multiline: false
  // Values offered as chips under the field (`x-suggestions`); a click
  // puts one in the field, or adds it to a comma-separated list
  property var suggestions: []
  property bool commaList: false
  // "folder": a Browse button beside the field opens the desktop's folder
  // picker (`x-control: "folder"`); the folder picked commits at once
  property string browse: ""

  // What was typed, once it matches `pattern`: on Enter (Ctrl+Enter in a
  // multiline field), as the field loses focus or is torn down. A picked
  // suggestion commits at once. Only an edit in the field emits it: never a
  // value pushed in (a selection switched, an editor reopened), which would
  // be written back onto whatever the form edits by then.
  signal valueEdited(string value)
  // Every keystroke's text, once it matches `pattern`, for a form that
  // can hold it unsaved without applying it (the settings page's draft):
  // applied live per keystroke, a font or a folder applied half-typed made
  // typing crawl (a notes folder ran `find` on `/`). Typed text also shows
  // its page's Save at once (EditsManager.holdTyping)
  signal valueTyped(string value)

  // Typed since the last commit or value pushed in
  property bool _typed: false
  on_TypedChanged: {
    if (!root._typed)
      EditsManager.releaseTyping(root);
  }
  // The Browse button's picker couldn't be shown (until a value commits)
  property bool _pickFailed: false

  readonly property string _text: textArea.text
  // The text as it reads back once committed: a list's typed "a, b," is
  // ["a", "b"], shown as "a, b"
  function _normalized(text) {
    return root.commaList ? text.split(",").map(v => v.trim()).filter(v => v !== "").join(", ") : text;
  }

  // The field shows the value that comes in, even while it has focus (what
  // it edits switched under it: kept, the old text would be typed onto the
  // new one), except the echo of what's being typed, which mustn't move
  // the cursor or eat a list's trailing ", "
  function _show() {
    const focused = textArea.input.activeFocus;
    if (root._text === root.currentConfigValue || (focused && root._normalized(root._text) === root.currentConfigValue))
      return;
    textArea.text = root.currentConfigValue;
    root._typed = false;
  }
  onCurrentConfigValueChanged: root._show()

  function _accept(text) {
    if (root.pattern === null || new RegExp(root.pattern).test(text)) {
      root._typed = false;
      root._pickFailed = false;
      root.valueEdited(text);
    }
  }

  function _type() {
    root._typed = true;
    EditsManager.holdTyping(root, root.Window.window);
    if (root.pattern === null || new RegExp(root.pattern).test(root._text))
      root.valueTyped(root._text);
  }

  // Commits what was typed, if anything was
  function _commitTyped() {
    if (root._typed)
      root._accept(root._text);
  }

  // Save: commits what was typed, or drops it if it isn't valid yet
  function commitTyped() {
    root._commitTyped();
    if (root._typed)
      root.discardTyped();
  }

  // Reset: back to the value
  function discardTyped() {
    textArea.text = root.currentConfigValue;
    root._typed = false;
  }

  // Don't lose an edit when the page goes away with the field focused
  Component.onDestruction: {
    root._commitTyped();
    EditsManager.releaseTyping(root);
    FilePickerManager.forget(root);
  }

  Layout.fillWidth: true
  spacing: Widget.spacing

  FieldHeader {
    label: root.label
    description: root.description
    trailing: root.headerExtra
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledTextArea {
      id: textArea
      Layout.fillWidth: true
      expandable: true
      // One line, wrapped up to four, then it scrolls (a long command)
      singleLine: !root.multiline
      maxLines: root.multiline ? 0 : 4
      // Enter is a new line in a multiline field: nothing to submit
      newlineOnEnter: root.multiline
      text: root.currentConfigValue

      onTextEdited: root._type()
      onAccepted: root._commitTyped()
      // Commits on leaving; half-typed text that never matched shows the
      // value again
      input.onActiveFocusChanged: {
        if (textArea.input.activeFocus)
          return;
        root._commitTyped();
        root._show();
      }
    }

    // Beside the first line, however many the value wraps to
    FlatIconButton {
      visible: root.browse === "folder"
      Layout.alignment: Qt.AlignTop
      size: Widget.height
      iconText: "folder_open"
      tooltipText: I18n.tr("Choose a folder")
      enabled: !FilePickerManager.running
      onClicked: {
        root._pickFailed = false;
        FilePickerManager.pick(root, I18n.tr(root.label), {
          "folder": true,
          "start": root.currentConfigValue,
          "shortenHome": true
        }, path => {
          textArea.text = path;
          root._accept(path);
        }, () => root._pickFailed = true);
      }
    }
  }

  Flow {
    visible: !root.multiline && root.suggestions.length > 0
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    Repeater {
      model: root.multiline ? [] : root.suggestions

      delegate: StyledTextButton {
        required property string modelData
        implicitHeight: Widget.height - Widget.px(8)
        text: modelData
        onClicked: {
          if (!root.commaList) {
            textArea.text = modelData;
            root._accept(modelData);
            return;
          }
          const items = textArea.text.split(",").map(v => v.trim()).filter(v => v !== "");
          if (!items.includes(modelData)) {
            textArea.text = items.concat([modelData]).join(", ");
            root._accept(textArea.text);
          }
        }
      }
    }
  }

  StyledText {
    visible: root._pickFailed
    text: I18n.tr("No file picker could be opened")
    color: Theme.warning
    textSize: Appearance.fontSizeBy(-2)
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }
}
