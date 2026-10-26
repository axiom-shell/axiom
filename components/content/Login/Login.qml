pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.content.base
import qs.components.content.parts
import qs.services.ui

// The greeter's login box (x-hosts: greeter only; x-required, so every
// greeter layout has one): who logs in and their password. It only logs
// in on the screen the greeter makes the target, in the real greeter: in
// the layouts editor's preview it's an inert box.
// properties: { userField, showAvatar, placeholder, centered, showMessages }
Card {
  id: root

  // The greeter surface's host: { kind: "greeter", target, preview, key,
  // bare, passwordBorder, greetingBorder }
  readonly property bool onGreeter: root.host?.kind === "greeter"
  readonly property bool live: root.onGreeter && root.host.target === true && root.host.preview !== true && Paths.greeter

  // The box draws its own fields, so no card around it: with the layout's
  // passwordBorder a box hugs them instead of filling the slot
  readonly property bool boxed: root.host?.passwordBorder === true
  readonly property real rowHeight: Widget.height + Widget.padding
  // A slot shorter than a field (one row on a doubled grid): the box takes
  // all of it, without the card's padding
  readonly property bool tight: root.height - root.pad * 2 < root.rowHeight
  readonly property real margin: root.tight ? 0 : root.pad
  readonly property real room: root.height - root.margin * 2 - (root.boxed ? Widget.padding * 2 : 0)
  // The fields' height: the user above the password where both fit (as
  // LoginField stacks them), else one row beside each other
  readonly property real stackedHeight: root.rowHeight * 2 + Widget.spacing
  readonly property real fieldsHeight: root.room >= root.stackedHeight ? root.stackedHeight : root.rowHeight
  // No room for greetd's messages under the password: they show in it
  readonly property bool inlineMessage: root.room < root.fieldsHeight + field.messageRoom

  color: "transparent"
  border.width: 0

  // Tells the greeter surface a Login module shows, so it doesn't draw its
  // own box
  property string _reportedKey: ""
  function _report() {
    const key = root.onGreeter ? (root.host.key ?? "") : "";
    if (key === root._reportedKey)
      return;
    SurfaceManager.reportRequiredField(root._reportedKey, false);
    SurfaceManager.reportRequiredField(key, true);
    root._reportedKey = key;
  }
  Component.onCompleted: root._report()
  onHostChanged: root._report()
  Component.onDestruction: SurfaceManager.reportRequiredField(root._reportedKey, false)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: root.margin
    height: Math.min(root.boxed ? field.implicitHeight + Widget.padding * 2 : Infinity, parent.height - root.margin * 2)
    radius: Widget.radius
    color: root.boxed ? Theme.background : "transparent"
    border.color: Theme.border
    border.width: root.boxed ? Appearance.borderWidth : 0

    LoginField {
      id: field
      anchors.fill: parent
      anchors.margins: root.boxed ? Widget.padding : 0
      active: root.live
      userField: root.properties.userField
      showAvatar: root.properties.showAvatar
      placeholder: root.properties.placeholder
      centered: root.properties.centered
      showMessages: root.properties.showMessages
      inlineMessage: root.inlineMessage
    }
  }
}
