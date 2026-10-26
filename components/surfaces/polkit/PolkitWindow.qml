pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.components.reusable
import qs.config
import qs.services.compositor
import qs.services.session
import qs.services.ui

// The polkit prompt on one screen: the whole screen dimmed, over the bars,
// and on the screen PolkitManager picked, a card with what is asking, the
// action, who to authenticate as and the password field. It's modal:
// clicks elsewhere do nothing, Escape or Cancel cancels the request. The
// password goes only to the request (PolkitManager.submit).
PanelWindow {
  id: root

  readonly property var flow: PolkitManager.flow
  readonly property bool shown: flow !== null
  // The card shows here: the picked screen, else (it's gone) the primary
  readonly property bool hasCard: !!screen && General.screensNamed(PolkitManager.screenName)[0] === screen
  readonly property int pad: 18

  // The request's fixed text, kept while the card fades out after it ends
  property string message: ""
  property string actionId: ""
  property string iconName: ""
  // Submitted, waiting for polkit's answer
  property bool checking: false
  // Briefly after it opens the field takes no keys, so typing meant for
  // another window doesn't land in it
  property bool settled: false

  onFlowChanged: {
    checking = false;
    if (!flow)
      return;
    message = flow.message;
    actionId = flow.actionId;
    iconName = flow.iconName;
    entry.input.text = "";
    settled = false;
    settle.restart();
    Qt.callLater(root.takeFocus);
  }

  // Every focus grab lets input through to it while it shows, so a prompt
  // over the overlay (the greeter's install, from Settings) closes nothing
  onVisibleChanged: visible ? SurfaceManager.registerModal(root) : SurfaceManager.unregisterModal(root)
  Component.onDestruction: SurfaceManager.unregisterModal(root)

  Timer {
    id: settle
    interval: 400
    onTriggered: root.settled = true
  }

  function takeFocus() {
    if (root.shown && root.hasCard)
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

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: root.hasCard
  visible: shown || dim.opacity > 0

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-polkit"
  WlrLayershell.keyboardFocus: root.shown && root.hasCard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // Where the compositor blurs only what a window asks: the whole dimmed
  // screen, while backdrops blur (LayerStack.blurBackdrops)
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.backdropRegions ? dimBlur : null)
  BoxBlurRegion {
    id: dimBlur
    target: dim
    opacity: dim.opacity
    alpha: dim.color.a
    threshold: 0.01
  }

  Rectangle {
    id: dim
    anchors.fill: parent
    color: Appearance.darkMode ? Theme.background : Theme.foreground
    opacity: root.shown ? 0.75 : 0

    Glide on opacity {
      duration: Appearance.animNormal
    }
  }

  // Modal: the dimmed screen takes clicks and does nothing with them
  MouseArea {
    anchors.fill: parent
  }

  Rectangle {
    id: card

    visible: root.hasCard
    anchors.centerIn: parent
    width: Math.min(Widget.px(480), root.width - Widget.px(32))
    height: content.implicitHeight + root.pad * 2
    color: Appearance.fill(Theme.background)
    border.color: Theme.border
    border.width: Appearance.borderWidth
    radius: Appearance.borderRadius

    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.97
    Glide on opacity {
      duration: Appearance.animNormal
    }
    Glide on scale {
      duration: Appearance.animNormal
    }

    ColumnLayout {
      id: content
      x: root.pad
      y: root.pad
      width: card.width - root.pad * 2
      spacing: root.pad

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
  }
}
