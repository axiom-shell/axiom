pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable

// What joining a Wi-Fi network asks for, by its security (net.join's):
// a password (WPA), a key (WEP), a user name and password (LEAP), or for
// enterprise networks (PEAP or TTLS) those with, under More, the inner
// method, an outer identity and how the server is checked (the system's
// CAs, a CA file, or not at all). `hidden` adds the network's name and a
// choice of security, for a network that doesn't broadcast. Enter in any
// field submits, Escape cancels.
ColumnLayout {
  id: root

  property bool hidden: false
  // "open", "psk", "wep", "eap", "dynamic-wep" or "leap"; a hidden
  // network's starts as "psk" and is chosen in the form
  property string security: "psk"
  // The last attempt's error, shown under the fields
  property string error: ""

  // fields: net.join's (ssid for a hidden one, security, password, …)
  signal submitted(var fields)
  signal cancelled

  readonly property bool enterprise: root.security === "eap" || root.security === "dynamic-wep"
  readonly property bool needsIdentity: root.enterprise || root.security === "leap"
  readonly property bool needsPassword: root.security !== "open"
  readonly property real fieldHeight: Widget.height

  property string eap: "peap"
  property string phase2: "mschapv2"
  // "system", "file" or "none"
  property string caMode: "system"
  property string caCert: ""
  property bool more: false

  readonly property bool complete: (!root.hidden || ssidField.text !== "") && (!root.needsIdentity || identityField.text !== "") && (!root.needsPassword || root.enterprise || passwordField.text !== "") && (root.caMode !== "file" || root.caCert !== "")

  function submit() {
    if (!root.complete)
      return;
    const fields = {
      "security": root.security,
      "password": passwordField.text,
      "identity": identityField.text,
      "anonymousIdentity": anonymousField.text,
      "eap": root.eap,
      "phase2": root.phase2,
      "caCert": root.caMode === "file" ? root.caCert : "",
      "systemCa": root.caMode === "system"
    };
    if (root.hidden) {
      fields.ssid = ssidField.text;
      fields.hidden = true;
    }
    root.submitted(fields);
  }

  function _focusFirst() {
    const first = root.hidden ? ssidField : root.needsIdentity ? identityField : passwordField;
    first.input.forceActiveFocus();
  }

  spacing: Widget.spacing
  Component.onCompleted: Qt.callLater(root._focusFirst)
  Component.onDestruction: FilePickerManager.forget(root)

  component Field: StyledTextEntry {
    Layout.fillWidth: true
    Layout.preferredHeight: root.fieldHeight
    input.wrapMode: Text.NoWrap
    onAccepted: root.submit()
    // The field leaves Escape to its parents
    Keys.onEscapePressed: root.cancelled()
  }

  // Beside the last field: the password, else (an open hidden network)
  // the name
  component ConnectButton: StyledRectButton {
    size: Widget.iconButton
    enabled: root.complete
    opacity: enabled ? 1 : 0.5
    iconText: "link"
    iconColor: Theme.accent
    backgroundColor: "transparent"
    borderHoverColor: Theme.accent
    tooltipText: I18n.tr("Connect")
    onClicked: root.submit()
  }

  RowLayout {
    visible: root.hidden
    Layout.fillWidth: true
    spacing: Widget.spacing

    Field {
      id: ssidField
      placeholderText: I18n.tr("Network name")
    }
    ConnectButton {
      visible: !root.needsPassword
    }
  }

  SegmentRow {
    visible: root.hidden
    Layout.fillWidth: true

    Repeater {
      // I18n.tr("None") I18n.tr("WPA") I18n.tr("WEP") I18n.tr("Enterprise")
      model: [["open", "None"], ["psk", "WPA"], ["wep", "WEP"], ["eap", "Enterprise"]]

      SegmentButton {
        required property var modelData
        text: I18n.tr(modelData[1])
        active: root.security === modelData[0]
        onClicked: root.security = modelData[0]
      }
    }
  }

  SegmentRow {
    visible: root.enterprise
    Layout.fillWidth: true

    SegmentButton {
      text: "PEAP"
      active: root.eap === "peap"
      onClicked: root.eap = "peap"
    }
    SegmentButton {
      text: "TTLS"
      active: root.eap === "ttls"
      onClicked: root.eap = "ttls"
    }
  }

  Field {
    id: identityField
    visible: root.needsIdentity
    placeholderText: I18n.tr("User name")
  }

  RowLayout {
    visible: root.needsPassword
    Layout.fillWidth: true
    spacing: Widget.spacing

    Field {
      id: passwordField
      placeholderText: root.security === "wep" ? I18n.tr("Key or passphrase") : I18n.tr("Password")
      input.echoMode: TextInput.Password
    }
    ConnectButton {}
  }

  // The last attempt's error
  StyledText {
    visible: root.error !== ""
    Layout.fillWidth: true
    text: root.error
    wrapMode: Text.WordWrap
    textSize: Appearance.fontSizeBy(-3)
    textColor: Theme.error
  }

  // More: the inner method, an outer identity and the server's check
  FoldRow {
    id: moreRow
    visible: root.enterprise
    open: root.more
    onToggled: root.more = !root.more

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("More options")
      textSize: Appearance.fontSizeBy(-2)
      textColor: moreRow.hovered ? Theme.accent : Theme.foregroundAlt
    }
  }

  ColumnLayout {
    visible: root.enterprise && root.more
    Layout.fillWidth: true
    spacing: Widget.spacing

    SegmentRow {
      Layout.fillWidth: true

      Repeater {
        model: [["mschapv2", "MSCHAPv2"], ["pap", "PAP"], ["mschap", "MSCHAP"], ["gtc", "GTC"]]

        SegmentButton {
          required property var modelData
          text: modelData[1]
          active: root.phase2 === modelData[0]
          onClicked: root.phase2 = modelData[0]
        }
      }
    }

    Field {
      id: anonymousField
      placeholderText: I18n.tr("Anonymous identity (optional)")
    }

    SegmentRow {
      Layout.fillWidth: true

      Repeater {
        // I18n.tr("System CAs") I18n.tr("CA file") I18n.tr("Don't check")
        model: [["system", "System CAs"], ["file", "CA file"], ["none", "Don't check"]]

        SegmentButton {
          required property var modelData
          text: I18n.tr(modelData[1])
          active: root.caMode === modelData[0]
          onClicked: root.caMode = modelData[0]
        }
      }
    }

    RowLayout {
      visible: root.caMode === "file"
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        Layout.fillWidth: true
        text: root.caCert !== "" ? root.caCert : I18n.tr("No file chosen")
        elide: Text.ElideMiddle
        textSize: Appearance.fontSizeBy(-3)
        textColor: root.caCert !== "" ? Theme.foreground : Theme.foregroundAlt
      }
      FlatIconButton {
        iconText: "folder_open"
        tooltipText: I18n.tr("Choose the CA certificate")
        onClicked: FilePickerManager.pick(root, I18n.tr("CA certificate"), {
          "filter": I18n.tr("Certificates") + ":*.pem *.crt *.cer *.der"
        }, path => root.caCert = path)
      }
    }
  }
}
