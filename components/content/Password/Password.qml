pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.components.content.base
import qs.components.content.parts

// The lock screen's password field (x-hosts: lockscreen only; x-required,
// so every lock screen layout has one). It only unlocks on the screen the
// lock surface makes the target, on a real lock: in the layouts editor's
// preview, or anywhere else, it's an inert field.
// properties: { placeholder, centered, showMessages }
Card {
  id: root

  // The lock surface's host: { kind: "lockscreen", target, preview, key,
  // bare, passwordBorder, greetingBorder }
  readonly property bool onLockscreen: root.host?.kind === "lockscreen"
  readonly property bool live: root.onLockscreen && root.host.target === true && root.host.preview !== true

  // The field draws its own box, so no card around it: with the lock
  // screen's passwordBorder (independent of its moduleBorders) a box hugs
  // the field instead of filling the slot
  readonly property bool boxed: root.host?.passwordBorder === true
  readonly property real boxPad: root.boxed ? Widget.padding : 0
  // A slot shorter than a field (one row on a doubled grid): the box takes
  // all of it, without the card's padding, and the field shrinks to fit
  readonly property real rowHeight: Widget.height + Widget.padding
  readonly property bool tight: root.height - root.pad * 2 - root.boxPad * 2 < root.rowHeight
  readonly property real margin: root.tight ? 0 : root.pad
  readonly property real room: root.height - root.margin * 2 - root.boxPad * 2
  // No room for the messages under the field: they show in it
  readonly property bool inlineMessage: root.room < root.rowHeight + field.messageRoom

  color: "transparent"
  border.width: 0

  // Tells the lock surface a Password module shows, so it doesn't draw its
  // own field
  property string _reportedKey: ""
  function _report() {
    const key = root.onLockscreen ? (root.host.key ?? "") : "";
    if (key === root._reportedKey)
      return;
    ShellManager.reportRequiredField(root._reportedKey, false);
    ShellManager.reportRequiredField(key, true);
    root._reportedKey = key;
  }
  Component.onCompleted: root._report()
  onHostChanged: root._report()
  Component.onDestruction: ShellManager.reportRequiredField(root._reportedKey, false)

  // Boxed, it's drawn like LockSurface's fallback field: a box as tall as
  // the field plus padding, across the slot. Its height doesn't change
  // with the messages: their line is kept, or they show in the field
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: root.margin
    height: root.boxed ? field.implicitHeight + root.boxPad * 2 : parent.height - root.margin * 2
    radius: Widget.radius
    color: root.boxed ? Theme.background : "transparent"
    border.color: Theme.border
    border.width: root.boxed ? Appearance.borderWidth : 0

    PasswordField {
      id: field
      anchors.fill: parent
      anchors.margins: root.boxPad
      active: root.live
      fieldHeight: root.room > 0 ? Math.min(root.rowHeight, root.room) : root.rowHeight
      inlineMessage: root.inlineMessage
      placeholder: root.properties.placeholder
      centered: root.properties.centered
      showMessages: root.properties.showMessages
    }
  }
}
