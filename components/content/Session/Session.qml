pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base

// The greeter's session picker (x-hosts: greeter only): which desktop the
// login starts (Wayland sessions; the user's last one to begin with). In
// the layouts editor's preview it only shows a name.
Card {
  id: root

  readonly property bool live: root.host?.kind === "greeter" && root.host.preview !== true && Paths.greeter
  // A slot shorter than the field (one row on a doubled grid): the field
  // is the whole module, with no card around it
  readonly property bool tight: root.height - root.pad * 2 < Widget.height
  readonly property real margin: root.tight ? 0 : root.pad

  color: root.tight || root.bare ? "transparent" : Theme.background
  border.width: root.tight || root.bare ? 0 : Appearance.borderWidth

  StyledComboEntry {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: root.margin
    height: Math.min(parent.height - root.margin * 2, implicitHeight * 1.4)
    icon: "desktop_windows"
    readOnly: !root.live
    options: root.live ? GreetdManager.sessions.map(session => ({
          "value": session.id,
          "label": session.name
        })) : []
    value: root.live ? (GreetdManager.selectedSession?.id ?? "") : I18n.tr("Session")
    onPicked: value => GreetdManager.selectSession(value)
  }
}
