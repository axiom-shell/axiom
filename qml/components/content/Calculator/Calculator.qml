pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.system
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Math, units and currencies through qalc (CalculatorManager), as the
// launcher's "=" does: the answer shows as you type, Enter (or a click on
// it) copies it and keeps it in the history below, or beside it in a wide
// card. A history row puts its answer back on the clipboard; its arrow
// puts the expression back in the field. With room (and in the popout) a
// keypad sits under the field, typing where the cursor is; its = moves the
// answer into the field to carry on from, as a pocket calculator does. A
// short card is one row: the field and the answer.
// properties: { showHistory, showKeypad }
Panel {
  id: root

  // Its own slot in the manager, so it never takes the launcher's answer
  readonly property string key: "module:" + String(root)
  readonly property string expr: field.text.trim()
  // The answer = put in the field: qalc only echoes it back (which reads
  // as no answer), so while the field still holds it, it is its own
  property string carried: ""
  readonly property string result: {
    const answer = CalculatorManager.resultFor(root.key, root.expr);
    return answer !== "" ? answer : root.expr !== "" && root.expr === root.carried ? root.carried : "";
  }
  readonly property bool missing: CalculatorManager.qalc === false
  readonly property var history: CalculatorManager.history
  // The last answer copied, for a moment, as feedback
  property string copied: ""

  // One row: the field and the answer side by side
  readonly property bool strip: root.embedded && root.innerHeight < Appearance.fontSize * 7
  // The height the keys can have: a wide card's whole height beside the
  // field, else what's left under the header, the field and a line of
  // answer
  readonly property real keypadRoom: !root.embedded ? 0 : root.sideBySide ? root.innerHeight : root.innerHeight - (root.showHeader ? Appearance.fontSize * 2 : 0) - Widget.height - Appearance.fontSize * 4 - root.spacing * 3
  // Keys beside the field in a wide card, under it in a tall one, while
  // five rows of them fit; always in the popout
  readonly property bool showKeypad: (root.properties.showKeypad ?? true) && !root.strip && (!root.embedded || (root.keypadRoom >= Appearance.fontSize * 2 * 5 && root.innerWidth >= Appearance.fontSize * 10))
  // Under the field; in a tall card only without the keypad
  readonly property bool showHistory: (root.properties.showHistory ?? true) && root.history.length > 0 && !root.strip && root.embedded && (root.sideBySide ? root.innerHeight >= Appearance.fontSize * 9 : !root.showKeypad && root.innerHeight >= Appearance.fontSize * 11)
  readonly property bool sideBySide: root.embedded && root.innerWidth >= Appearance.fontSize * 30 && root.innerWidth >= root.innerHeight * 1.3
  readonly property bool showHeader: root.embedded && !root.strip && root.innerHeight >= Appearance.fontSize * 9

  implicitWidth: Widget.px(360)
  fullMinWidth: Appearance.fontSize * 11
  fullMinHeight: Appearance.fontSize * 3.5
  wantsKeyboardFocus: true
  spacing: Widget.spacing

  function copyResult() {
    if (root.result === "")
      return;
    ClipboardManager.copyText(root.result);
    CalculatorManager.keep(root.expr, root.result);
    root.copied = root.result;
    copiedReset.restart();
  }

  // A keypad key: "=" takes the answer into the field, "C" clears it, "⌫"
  // deletes before the cursor, anything else is typed at the cursor
  function press(key) {
    const input = field.input;
    if (key === "=") {
      if (root.result === "" || root.expr === root.carried)
        return;
      CalculatorManager.keep(root.expr, root.result);
      root.carried = root.result;
      field.text = root.result;
      input.cursorPosition = field.text.length;
    } else if (key === "C") {
      field.text = "";
    } else if (key === "⌫") {
      if (input.selectedText !== "")
        input.remove(input.selectionStart, input.selectionEnd);
      else if (input.cursorPosition > 0)
        input.remove(input.cursorPosition - 1, input.cursorPosition);
    } else {
      if (input.selectedText !== "")
        input.remove(input.selectionStart, input.selectionEnd);
      input.insert(input.cursorPosition, key);
    }
    input.forceActiveFocus();
  }

  function copyAnswer(entry) {
    ClipboardManager.copyText(entry.result);
    CalculatorManager.keep(entry.expr, entry.result);
    root.copied = entry.result;
    copiedReset.restart();
  }

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copied = ""
  }

  Component.onCompleted: {
    field.text = CalculatorManager.draft;
    DependencyManager.check(["qalc"]);
  }
  Component.onDestruction: CalculatorManager.forget(root.key)

  compactContent: CompactFigure {
    readonly property var last: root.history[0] ?? null
    icon: "calculate"
    value: root.result || (last?.result ?? "")
    label: root.result ? root.expr : (last?.expr ?? I18n.tr("Calculator"))
  }

  // One key: a digit, an operator (tinted) or = (filled), or an icon
  component Key: Rectangle {
    id: key
    required property var modelData
    readonly property string kind: modelData.kind ?? "digit"
    readonly property bool hot: hover.hovered || tap.pressed

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.columnSpan: modelData.span ?? 1
    Layout.preferredWidth: (modelData.span ?? 1) * 10
    Layout.preferredHeight: 10 // fixed px: a layout weight, not a size
    radius: Widget.radius
    color: key.kind === "equals" ? (key.hot ? Qt.lighter(Theme.accent, 1.1) : Theme.accent) : key.kind === "op" ? Qt.alpha(Theme.accent, key.hot ? 0.3 : 0.16) : key.hot ? Theme.backgroundHighlight : Theme.backgroundAlt
    scale: tap.pressed ? 0.94 : 1

    ColorGlide on color {}
    Glide on scale {}

    StyledText {
      visible: !key.modelData.icon
      anchors.centerIn: parent
      text: key.modelData.label ?? key.modelData.key
      textSize: Math.max(Appearance.fontSizeBy(-2), Math.min(Appearance.fontSize * 1.5, key.height * 0.38))
      textColor: key.kind === "equals" ? Theme.background : key.kind === "op" ? Theme.accent : Theme.foreground
      font.bold: key.kind !== "digit"
    }
    StyledIcon {
      visible: !!key.modelData.icon
      anchors.centerIn: parent
      text: key.modelData.icon ?? ""
      textSize: Math.max(Appearance.fontSizeBy(-2), Math.min(Appearance.fontSize * 1.5, key.height * 0.38))
      textColor: Theme.accent
    }

    HoverHandler {
      id: hover
      cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
      id: tap
      onTapped: root.press(key.modelData.key)
    }
  }

  // The keys, four across; the scientific row on top when there's room.
  // Kept to a pocket calculator's proportions in a big card
  component Keypad: GridLayout {
    id: keypad
    readonly property bool scientific: !root.embedded || root.keypadRoom >= Appearance.fontSize * 2.6 * 6
    readonly property var keys: (keypad.scientific ? [
        {
          "key": "√(",
          "label": "√",
          "kind": "op"
        },
        {
          "key": "^",
          "label": "xʸ",
          "kind": "op"
        },
        {
          "key": "%",
          "kind": "op"
        },
        {
          "key": "π",
          "kind": "op"
        }
      ] : []).concat([
      {
        "key": "C",
        "kind": "op"
      },
      {
        "key": "(",
        "kind": "op"
      },
      {
        "key": ")",
        "kind": "op"
      },
      {
        "key": "÷",
        "kind": "op"
      },
      {
        "key": "7"
      },
      {
        "key": "8"
      },
      {
        "key": "9"
      },
      {
        "key": "×",
        "kind": "op"
      },
      {
        "key": "4"
      },
      {
        "key": "5"
      },
      {
        "key": "6"
      },
      {
        "key": "−",
        "kind": "op"
      },
      {
        "key": "1"
      },
      {
        "key": "2"
      },
      {
        "key": "3"
      },
      {
        "key": "+",
        "kind": "op"
      },
      {
        "key": "0"
      },
      {
        "key": "."
      },
      {
        "key": "⌫",
        "icon": "backspace",
        "kind": "op"
      },
      {
        "key": "=",
        "kind": "equals"
      }
    ])
    readonly property int keyRows: keypad.keys.length / 4

    Layout.fillWidth: true
    // Beside the field it takes the card's height; under it, as much of
    // the room as it wants, the display taking the rest
    Layout.fillHeight: root.embedded && root.sideBySide
    Layout.preferredWidth: 1
    // Keys never wider than 1.7 times their height
    Layout.maximumWidth: Math.min(Appearance.fontSize * 26, root.embedded ? Math.min(root.keypadRoom, keypad.keyRows * Appearance.fontSize * 4) / keypad.keyRows * 4 * 1.7 : Number.POSITIVE_INFINITY)
    Layout.maximumHeight: keypad.keyRows * Appearance.fontSize * 4
    Layout.preferredHeight: root.embedded ? Math.min(keypad.keyRows * Appearance.fontSize * 4, root.keypadRoom) : keypad.keyRows * Appearance.fontSize * 2.6
    Layout.alignment: root.sideBySide ? Qt.AlignCenter : Qt.AlignHCenter | Qt.AlignBottom
    columns: 4
    columnSpacing: Widget.spacing / 2
    rowSpacing: Widget.spacing / 2

    Repeater {
      model: keypad.keys
      delegate: Key {}
    }
  }

  ModuleHeader {
    visible: root.showHeader
    icon: "calculate"
    title: I18n.tr("Calculator")
    FlatIconButton {
      visible: root.history.length > 0
      size: Widget.iconButton
      iconText: "delete_sweep"
      tooltipText: I18n.tr("Clear the history")
      onClicked: CalculatorManager.clearHistory()
    }
  }

  // Where qalc isn't installed
  Item {
    visible: root.missing
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: root.embedded ? -1 : Appearance.fontSize * 6
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: "calculate"
      text: I18n.tr("The calculator needs qalc (libqalculate)")
    }
  }

  GridLayout {
    visible: !root.missing
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    // The field and the answer, and the history under them
    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.fillHeight: root.embedded
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing

      GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: root.embedded && !root.showHistory
        columns: root.strip ? 2 : 1
        columnSpacing: Widget.spacing
        rowSpacing: Widget.spacing

        StyledTextEntry {
          id: field
          Layout.fillWidth: true
          Layout.preferredWidth: root.strip ? 3 : 1 // fixed px: layout weights, not sizes
          Layout.preferredHeight: Widget.height
          placeholderText: I18n.tr("e.g. 5 km to mi")
          input.wrapMode: Text.NoWrap
          onTextChanged: {
            CalculatorManager.setDraft(text);
            if (CalculatorManager.qalc !== false)
              CalculatorManager.evaluate(root.key, text);
          }
          onAccepted: root.copyResult()
          Keys.onEscapePressed: event => {
            if (field.text === "") {
              event.accepted = false;
              return;
            }
            field.text = "";
          }
        }

        // The answer: big, click to copy. With the card to itself it's
        // centred in the room under the field (a hint until there's an
        // expression); over the history it sits right, under the field
        Item {
          id: answerBox
          readonly property bool centred: root.embedded && !root.strip && !root.showHistory && !root.showKeypad
          // Over a keypad in a tall card: the room between the field and
          // the keys, the answer at its foot, as on a calculator's display
          readonly property bool display: root.embedded && root.showKeypad && !root.sideBySide && !root.showHistory
          Layout.fillWidth: true
          Layout.preferredWidth: root.strip ? 2 : 1
          Layout.fillHeight: answerBox.centred || answerBox.display
          Layout.preferredHeight: answerColumn.implicitHeight
          Layout.minimumHeight: answer.implicitHeight

          EmptyState {
            visible: answerBox.centred && root.expr === ""
            anchors.centerIn: parent
            maxWidth: parent.width
            availableHeight: parent.height
            icon: "calculate"
            text: I18n.tr("Math, units and currencies, e.g. 5 km to mi")
          }

          ColumnLayout {
            id: answerColumn
            visible: !(answerBox.centred && root.expr === "")
            anchors.left: parent.left
            anchors.right: parent.right
            // Centred, at the foot (a display) or at the top
            y: answerBox.centred || root.strip ? (parent.height - height) / 2 : answerBox.display ? parent.height - height : 0
            spacing: 0

            StyledText {
              id: answer
              Layout.fillWidth: true
              horizontalAlignment: answerBox.centred ? Text.AlignHCenter : root.strip ? Text.AlignLeft : Text.AlignRight
              text: root.result !== "" ? "= " + root.result : root.expr !== "" && CalculatorManager.busyFor(root.key) ? "…" : ""
              textSize: root.strip ? Appearance.fontSizeBy(2) : (answerBox.centred || answerBox.display) && root.innerHeight >= Appearance.fontSize * 12 ? Appearance.fontSize * 2.2 : Appearance.fontSize * 1.6
              textColor: root.copied !== "" && root.copied === root.result ? Theme.accent : Theme.foreground
              font.bold: true
              wrapMode: answerBox.centred ? Text.Wrap : Text.NoWrap
              maximumLineCount: answerBox.centred ? 3 : 1
              elide: answerBox.centred ? Text.ElideRight : Text.ElideLeft

              ColorGlide on textColor {}

              MouseArea {
                anchors.fill: parent
                enabled: root.result !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyResult()
              }
            }
            StyledText {
              elide: Text.ElideRight
              visible: !root.strip
              Layout.fillWidth: true
              horizontalAlignment: answerBox.centred ? Text.AlignHCenter : Text.AlignRight
              text: root.copied !== "" ? I18n.tr("Copied") : root.result !== "" ? I18n.tr("Enter to copy") : root.expr !== "" && CalculatorManager.answered(root.key, root.expr) ? I18n.tr("No result") : I18n.tr("Math, units and currencies")
              textSize: Appearance.fontSizeBy(-3)
              textColor: Theme.foregroundAlt
            }
          }
        }
      }

      // Answers kept, newest first
      StyledScrollView {
        id: historyScroll
        visible: root.showHistory
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: root.embedded
        Layout.preferredHeight: root.embedded ? -1 : Math.min(historyList.implicitHeight, Appearance.fontSize * 16)
        contentPadding: 0
        showScrollBar: historyList.implicitHeight > height

        ColumnLayout {
          id: historyList
          width: historyScroll.availableWidth
          spacing: 2

          Repeater {
            model: root.history.length

            ItemRow {
              id: row
              required property int index
              readonly property var entry: root.history[index] ?? ({
                  "expr": "",
                  "result": ""
                })
              icon: root.copied === entry.result ? "check" : "calculate"
              marked: root.copied === entry.result
              title: entry.result
              subtitle: entry.expr
              onActivated: root.copyAnswer(row.entry)

              FlatIconButton {
                size: Widget.iconButton
                iconText: "north_west"
                tooltipText: I18n.tr("Edit")
                onClicked: {
                  field.text = row.entry.expr;
                  field.input.forceActiveFocus();
                }
              }
            }
          }
        }
      }
    }

    // Beside them in a wide card, under them in a tall one
    Keypad {
      visible: root.showKeypad
    }
  }

  // Keeps a short card's row at the top
  Item {
    visible: root.embedded && !root.missing && root.strip
    Layout.fillHeight: true
  }
}
