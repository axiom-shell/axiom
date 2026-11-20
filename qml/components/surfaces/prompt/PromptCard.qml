pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.components.reusable
import qs.config
import qs.services.ui

// A PromptManager request's own card (PromptWindow): its icon, title and
// message, a code shown large (the digits a keyboard typed lit), its
// fields, its error and its action buttons. Enter runs the primary action
// once every field is filled; Escape cancels. For 400 ms after a request
// shows it takes no keys, so typing meant for another window doesn't
// answer it.
FocusScope {
  id: root

  // The request drawn (PromptManager.current, kept while it fades out)
  property var request: null
  // The window shows it, on this screen: it may take the keyboard
  property bool live: false

  readonly property string requestId: request?.id ?? ""
  readonly property var fields: request?.fields ?? []
  readonly property var actions: request?.actions ?? []
  readonly property var primary: actions.find(a => a.primary) ?? null
  readonly property bool busy: request?.busy ?? false
  readonly property int attempt: request?.attempt ?? 0
  // Every field holds something: the primary action may run
  readonly property bool filled: root._filled
  readonly property bool settled: settle.settled
  property bool _filled: root.fields.length === 0

  implicitHeight: content.implicitHeight

  onRequestIdChanged: {
    root._clear();
    settle.rearm();
    Qt.callLater(root.takeFocus);
  }

  // Asked again after a wrong answer: the fields clear and shake
  onAttemptChanged: {
    if (root.attempt === 0)
      return;
    root._clear();
    const last = fieldRepeater.itemAt(root.fields.length - 1) as PasswordEntry;
    if (last)
      last.shake();
    root.takeFocus();
  }

  onBusyChanged: {
    if (!root.busy)
      root.takeFocus();
  }

  PromptSettle {
    id: settle
  }

  function takeFocus() {
    if (!root.live || root.requestId === "")
      return;
    const first = fieldRepeater.itemAt(0) as PasswordEntry;
    if (first)
      first.input.forceActiveFocus();
    else
      root.forceActiveFocus();
  }

  // The fields' values, by key
  function values() {
    const out = {};
    for (let i = 0; i < root.fields.length; i++) {
      const item = fieldRepeater.itemAt(i) as PasswordEntry;
      out[root.fields[i].key] = item ? item.input.text : "";
    }
    return out;
  }

  function act(action) {
    if (!action || root.requestId === "" || root.busy || !root.settled)
      return;
    if (action.primary && !root.filled)
      return;
    // The request's change is the user's doing, as a menu's click is
    if (action.primary && root.request?.marks)
      ShellManager.onScreen(root.request.marks);
    PromptManager.answer(root.requestId, action.id, root.values());
  }

  function _clear() {
    for (let i = 0; i < fieldRepeater.count; i++) {
      const item = fieldRepeater.itemAt(i) as PasswordEntry;
      if (item)
        item.input.text = "";
    }
    root._refill();
  }

  function _refill() {
    let filled = true;
    for (let i = 0; i < root.fields.length; i++) {
      const item = fieldRepeater.itemAt(i) as PasswordEntry;
      if (!item || item.input.text === "")
        filled = false;
    }
    root._filled = filled;
  }

  Keys.onEscapePressed: {
    // Not while settling: an Escape meant for another window
    if (root.settled)
      PromptManager.cancel(root.requestId);
  }
  Keys.onReturnPressed: root.act(root.primary)
  Keys.onEnterPressed: root.act(root.primary)

  RegularExpressionValidator {
    id: digitsOnly
    regularExpression: /[0-9]*/
  }

  ColumnLayout {
    id: content
    width: root.width
    spacing: Style.space5

    // What is asking
    ModalHeader {
      Layout.fillWidth: true
      icon: root.request?.icon || "info"
      title: root.request?.title ?? ""
      message: root.request?.message ?? ""
    }

    // The code to compare or type, the digits typed lit
    Row {
      Layout.alignment: Qt.AlignHCenter
      visible: (root.request?.code ?? "") !== ""
      spacing: Widget.px(6)

      Repeater {
        model: (root.request?.code ?? "").split("")

        delegate: StyledText {
          required property string modelData
          required property int index
          readonly property int entered: root.request?.entered ?? -1
          text: modelData
          textFamily: "monospace"
          role: "display"
          font.weight: Style.weightStrong
          textColor: entered >= 0 && index < entered ? Style.textAccent : entered >= 0 ? Style.textFaint : Style.text
        }
      }
    }

    Repeater {
      id: fieldRepeater
      model: root.fields

      delegate: PasswordEntry {
        id: field
        required property var modelData
        required property int index
        readonly property bool last: index === root.fields.length - 1
        Layout.fillWidth: true
        placeholder: modelData.label
        horizontalAlignment: Text.AlignLeft
        reveal: !modelData.secret
        secret: modelData.secret === true
        readOnly: root.busy || !root.settled
        busy: root.busy && last
        message: last ? (root.request?.error ?? "") : ""
        messageIsError: true
        wrapMessage: true

        Component.onCompleted: {
          if (field.modelData.digits) {
            field.input.validator = digitsOnly;
            field.input.inputMethodHints = field.input.inputMethodHints | Qt.ImhDigitsOnly;
          }
          if (field.modelData.maxLength > 0)
            field.input.maximumLength = field.modelData.maxLength;
          root._refill();
        }

        Connections {
          target: field.input
          function onTextChanged() {
            root._refill();
          }
        }

        onAccepted: root.act(root.primary)
      }
    }

    // An error with no field to show it under
    StyledText {
      Layout.fillWidth: true
      visible: root.fields.length === 0 && text !== ""
      text: root.request?.error ?? ""
      tone: "error"
    }

    ModalFooter {
      Layout.fillWidth: true
      hints: (root.primary !== null ? [
          {
            "key": "↵",
            "label": (root.primary?.label ?? "").toLowerCase()
          }
        ] : []).concat([
        {
          "key": "Esc",
          "label": I18n.tr("cancel")
        }
      ])

      Repeater {
        model: root.actions

        delegate: StyledTextButton {
          required property var modelData
          readonly property bool primary: modelData.primary ?? false
          text: modelData.label
          iconText: modelData.icon ?? ""
          enabled: !root.busy && (!primary || root.filled)
          kind: primary ? "primary" : "tonal"
          onClicked: root.act(modelData)
        }
      }
    }
  }
}
