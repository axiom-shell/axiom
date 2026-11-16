pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.components.reusable
import qs.config
import qs.services.session

// The polkit request's card in the shared prompt (PromptWindow, for a
// request whose content is "polkit"): what is asking, the action, who to
// authenticate as and the password field. Escape or Cancel cancels the
// request. The password goes only to the request (PolkitManager.submit).
ColumnLayout {
  id: root

  // The window shows it, on this screen: it may take the keyboard
  property bool live: false

  readonly property var flow: PolkitManager.flow

  // The request's fixed text, kept while the card fades out after it ends
  property string message: ""
  property string actionId: ""
  property string iconName: ""
  // Submitted, waiting for polkit's answer
  property bool checking: false
  // Briefly after it opens the field takes no keys, so typing meant for
  // another window doesn't land in it
  readonly property bool settled: settle.settled

  spacing: Style.space5

  onFlowChanged: root._take()
  Component.onCompleted: root._take()

  function _take() {
    root.checking = false;
    if (!root.flow)
      return;
    root.message = root.flow.message;
    root.actionId = root.flow.actionId;
    root.iconName = root.flow.iconName;
    entry.input.text = "";
    settle.rearm();
    Qt.callLater(root.takeFocus);
  }

  PromptSettle {
    id: settle
  }

  function takeFocus() {
    if (root.live && root.flow)
      entry.input.forceActiveFocus();
  }

  function submit() {
    if (!root.flow || !root.flow.isResponseRequired || entry.input.text.length === 0)
      return;
    root.checking = true;
    PolkitManager.submit(entry.input.text);
    entry.input.text = "";
  }

  function identityLabel(identity) {
    if (!identity)
      return "";
    const name = identity.string;
    return identity.displayName && identity.displayName !== name ? I18n.tr("{0} ({1})", identity.displayName, name) : name;
  }

  Connections {
    target: root.flow
    ignoreUnknownSignals: true

    function onAuthenticationFailed() {
      root.checking = false;
      entry.input.text = "";
      entry.shake();
      root.takeFocus();
    }

    function onIsResponseRequiredChanged() {
      if (root.flow?.isResponseRequired) {
        root.checking = false;
        root.takeFocus();
      }
    }
  }

  // What is asking
  PromptHeader {
    Layout.fillWidth: true
    icon: "admin_panel_settings"
    iconSource: root.iconName !== "" ? Quickshell.iconPath(root.iconName, true) : ""
    title: I18n.tr("Authentication required")
    message: root.message
  }

  // The action
  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing / 2

    StyledText {
      visible: actionDescription.visible
      text: I18n.tr("Action")
      tone: "muted"
    }
    StyledText {
      id: actionDescription
      Layout.fillWidth: true
      visible: text !== ""
      text: PolkitManager.actionInfo.description ?? ""
    }

    StyledText {
      visible: vendor.visible
      text: I18n.tr("From")
      tone: "muted"
    }
    StyledText {
      id: vendor
      Layout.fillWidth: true
      visible: text !== ""
      text: PolkitManager.actionInfo.vendor ?? ""
    }

    StyledText {
      visible: root.actionId !== ""
      text: I18n.tr("Action ID")
      tone: "muted"
    }
    StyledText {
      Layout.fillWidth: true
      visible: root.actionId !== ""
      text: root.actionId
      textFamily: "monospace"
      role: "caption"
      overflow: "line"
      elide: Text.ElideMiddle // style-exempt: middle
    }

    StyledText {
      visible: (root.flow?.identities.length ?? 0) === 1
      text: I18n.tr("As")
      tone: "muted"
    }
    StyledText {
      Layout.fillWidth: true
      visible: (root.flow?.identities.length ?? 0) === 1
      text: root.identityLabel(root.flow?.selectedIdentity)
      overflow: "line"
    }
  }

  // Who to authenticate as, when there's a choice
  ColumnLayout {
    Layout.fillWidth: true
    visible: (root.flow?.identities.length ?? 0) > 1
    spacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Authenticate as")
      tone: "muted"
    }

    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing

      Repeater {
        model: root.flow?.identities ?? []

        delegate: StyledTextButton {
          required property var modelData
          readonly property bool selected: root.flow?.selectedIdentity === modelData
          text: root.identityLabel(modelData)
          iconText: modelData.isGroup ? "group" : "person"
          kind: selected ? "primary" : "tonal"
          onClicked: {
            PolkitManager.selectIdentity(modelData);
            root.takeFocus();
          }
        }
      }
    }
  }

  // The answer
  PasswordEntry {
    id: entry
    Layout.fillWidth: true
    placeholder: (root.flow?.inputPrompt ?? "").trim().replace(/:$/, "") || I18n.tr("Password")
    centered: false
    readOnly: !(root.flow?.isResponseRequired ?? false) || root.checking || !root.settled
    reveal: root.flow?.responseVisible ?? false
    message: root.flow?.supplementaryMessage ?? ""
    messageIsError: root.flow?.supplementaryIsError ?? false
    wrapMessage: true
    busy: root.checking

    Keys.onEscapePressed: PolkitManager.cancel()
    onAccepted: root.submit()
  }

  PromptFooter {
    Layout.fillWidth: true
    hints: [
      {
        "key": "↵",
        "label": I18n.tr("authenticate")
      },
      {
        "key": "Esc",
        "label": I18n.tr("cancel")
      }
    ]

    StyledTextButton {
      text: I18n.tr("Cancel")
      onClicked: PolkitManager.cancel()
    }

    StyledTextButton {
      text: I18n.tr("Authenticate")
      iconText: "lock_open"
      kind: "primary"
      onClicked: root.submit()
    }
  }
}
