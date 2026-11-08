pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

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
  property int pad: Widget.px(18)

  readonly property var flow: PolkitManager.flow

  // The request's fixed text, kept while the card fades out after it ends
  property string message: ""
  property string actionId: ""
  property string iconName: ""
  // Submitted, waiting for polkit's answer
  property bool checking: false
  // Briefly after it opens the field takes no keys, so typing meant for
  // another window doesn't land in it
  property bool settled: false

  spacing: root.pad

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
    root.settled = false;
    settle.restart();
    Qt.callLater(root.takeFocus);
  }

  Timer {
    id: settle
    interval: 400
    onTriggered: root.settled = true
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
  RowLayout {
    Layout.fillWidth: true
    spacing: root.pad

    Item {
      Layout.alignment: Qt.AlignTop
      implicitWidth: Widget.px(40)
      implicitHeight: Widget.px(40)

      IconImage {
        id: appIcon
        anchors.fill: parent
        source: root.iconName !== "" ? Quickshell.iconPath(root.iconName, true) : ""
        visible: source.toString() !== ""
      }

      StyledIcon {
        anchors.centerIn: parent
        visible: !appIcon.visible
        text: "admin_panel_settings"
        textColor: Theme.accent
        textSize: Widget.px(32)
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Authentication required")
        textSize: Appearance.fontSizeLarge
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
      }

      StyledText {
        Layout.fillWidth: true
        text: root.message
        wrapMode: Text.WordWrap
      }
    }
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
      opacity: 0.7
    }
    StyledText {
      id: actionDescription
      Layout.fillWidth: true
      visible: text !== ""
      text: PolkitManager.actionInfo.description ?? ""
      wrapMode: Text.WordWrap
    }

    StyledText {
      visible: vendor.visible
      text: I18n.tr("From")
      opacity: 0.7
    }
    StyledText {
      id: vendor
      Layout.fillWidth: true
      visible: text !== ""
      text: PolkitManager.actionInfo.vendor ?? ""
      wrapMode: Text.WordWrap
    }

    StyledText {
      visible: root.actionId !== ""
      text: I18n.tr("Action ID")
      opacity: 0.7
    }
    StyledText {
      Layout.fillWidth: true
      visible: root.actionId !== ""
      text: root.actionId
      textFamily: "monospace"
      textSize: Appearance.fontSizeBy(-1)
      elide: Text.ElideMiddle
    }

    StyledText {
      visible: (root.flow?.identities.length ?? 0) === 1
      text: I18n.tr("As")
      opacity: 0.7
    }
    StyledText {
      Layout.fillWidth: true
      visible: (root.flow?.identities.length ?? 0) === 1
      text: root.identityLabel(root.flow?.selectedIdentity)
      elide: Text.ElideRight
    }
  }

  // Who to authenticate as, when there's a choice
  ColumnLayout {
    Layout.fillWidth: true
    visible: (root.flow?.identities.length ?? 0) > 1
    spacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Authenticate as")
      opacity: 0.7
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
          backgroundColor: selected ? Theme.accent : Theme.backgroundHighlight
          textColor: selected ? Theme.background : Theme.foreground
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

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    Row {
      Layout.fillWidth: true
      spacing: Widget.padding

      KeyHint {
        key: "↵"
        label: I18n.tr("authenticate")
      }
      KeyHint {
        key: "Esc"
        label: I18n.tr("cancel")
      }
    }

    StyledTextButton {
      text: I18n.tr("Cancel")
      onClicked: PolkitManager.cancel()
    }

    StyledTextButton {
      text: I18n.tr("Authenticate")
      iconText: "lock_open"
      backgroundColor: Theme.accent
      textColor: Theme.background
      onClicked: root.submit()
    }
  }
}
