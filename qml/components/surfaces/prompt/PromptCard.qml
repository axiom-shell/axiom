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
  property int pad: Widget.px(18)

  readonly property string requestId: request?.id ?? ""
  readonly property var fields: request?.fields ?? []
  readonly property var actions: request?.actions ?? []
  readonly property var primary: actions.find(a => a.primary) ?? null
  readonly property bool busy: request?.busy ?? false
  readonly property int attempt: request?.attempt ?? 0
  // Every field holds something: the primary action may run
  readonly property bool filled: root._filled
  property bool settled: false
  property bool _filled: root.fields.length === 0

  implicitHeight: content.implicitHeight

  onRequestIdChanged: {
    root._clear();
    root.settled = false;
    settle.restart();
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

  Timer {
    id: settle
    interval: 400
    onTriggered: root.settled = true
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

  Keys.onEscapePressed: PromptManager.cancel(root.requestId)
  Keys.onReturnPressed: root.act(root.primary)
  Keys.onEnterPressed: root.act(root.primary)

  RegularExpressionValidator {
    id: digitsOnly
    regularExpression: /[0-9]*/
  }

  ColumnLayout {
    id: content
    width: root.width
    spacing: root.pad

    // What is asking
    RowLayout {
      Layout.fillWidth: true
      spacing: root.pad

      Item {
        Layout.alignment: Qt.AlignTop
        implicitWidth: Widget.px(40)
        implicitHeight: Widget.px(40)

        StyledIcon {
          anchors.centerIn: parent
          text: root.request?.icon || "info"
          textColor: Theme.accent
          textSize: Widget.px(32)
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledText {
          Layout.fillWidth: true
          text: root.request?.title ?? ""
          textSize: Appearance.fontSizeLarge
          font.weight: Font.DemiBold
          wrapMode: Text.WordWrap
        }

        StyledText {
          Layout.fillWidth: true
          visible: text !== ""
          text: root.request?.message ?? ""
          wrapMode: Text.WordWrap
        }
      }
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
          textSize: Appearance.fontSizeBy(14)
          font.weight: Font.DemiBold
          textColor: entered >= 0 && index < entered ? Theme.accent : Theme.foreground
          opacity: entered >= 0 && index >= entered ? 0.6 : 1
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
        centered: false
        reveal: !modelData.secret
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
      textColor: Theme.error
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      Row {
        Layout.fillWidth: true
        spacing: Widget.padding

        KeyHint {
          visible: root.primary !== null
          key: "↵"
          label: (root.primary?.label ?? "").toLowerCase()
        }
        KeyHint {
          key: "Esc"
          label: I18n.tr("cancel")
        }
      }

      Repeater {
        model: root.actions

        delegate: StyledTextButton {
          required property var modelData
          readonly property bool primary: modelData.primary ?? false
          text: modelData.label
          iconText: modelData.icon ?? ""
          enabled: !root.busy && (!primary || root.filled)
          opacity: enabled ? 1 : 0.5
          backgroundColor: primary ? Theme.accent : Theme.backgroundHighlight
          textColor: primary ? Theme.background : Theme.foreground
          onClicked: root.act(modelData)
        }
      }
    }
  }
}
