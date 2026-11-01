pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// One VPN in a VPN list (VpnManager.rows): its kind, name and status,
// connect / disconnect, and while NetworkManager asks for its password
// (VpnManager.secretRequest) a field for each secret under it, as the
// Wi-Fi menu asks for a network's password. Clicking the row toggles it.
DeviceRow {
  id: row

  required property var vpn
  readonly property var request: VpnManager.secretRequest
  readonly property bool asking: row.vpn !== null && row.request !== null && row.request.uuid === row.vpn.id

  icon: VpnManager.kindIcon(row.vpn?.kind ?? "")
  title: row.vpn?.name ?? ""
  status: VpnManager.statusText(row.vpn)
  failed: (row.vpn?.error ?? "") !== ""
  connected: row.vpn?.state === "on"
  busy: VpnManager.busy(row.vpn)
  selected: row.asking
  expanded: row.asking
  onActivated: {
    if (row.asking)
      VpnManager.cancelSecret();
    else
      VpnManager.toggle(row.vpn);
  }
  onConnectClicked: VpnManager.toggle(row.vpn)

  // The secrets asked for: built only while asked (each ask starts empty)
  Loader {
    width: parent.width
    active: row.asking

    sourceComponent: ColumnLayout {
      id: form
      spacing: Widget.spacing

      // key -> text typed
      property var values: ({})
      readonly property bool complete: (row.request?.fields ?? []).every(k => (form.values[k] ?? "") !== "")

      function submit() {
        if (form.complete)
          VpnManager.answerSecret(form.values);
      }

      StyledText {
        Layout.fillWidth: true
        visible: text !== ""
        text: row.request?.message || (row.request?.user ? I18n.tr("Signing in as {0}", row.request.user) : "")
        wrapMode: Text.WordWrap
        textSize: Appearance.fontSizeBy(-3)
        textColor: Theme.foregroundAlt
      }

      Repeater {
        model: row.request?.fields ?? []

        SecretField {
          id: fieldRow
          required property string modelData
          required property int index
          placeholderText: VpnManager.fieldLabel(fieldRow.modelData)
          // One button, after the last field
          buttonShown: fieldRow.index === (row.request?.fields ?? []).length - 1
          canSubmit: form.complete
          focusOnShow: fieldRow.index === 0
          onTextChanged: {
            const next = Object.assign({}, form.values);
            next[fieldRow.modelData] = fieldRow.text;
            form.values = next;
          }
          onSubmitted: form.submit()
          onCancelled: VpnManager.cancelSecret()
        }
      }
    }
  }
}
