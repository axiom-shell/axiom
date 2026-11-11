pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.bar.widgets.base

// Caps Lock, Num Lock and Scroll Lock (those its settings show), from
// LockKeysManager (the keyboards' LEDs), a glyph each in its lead slot.
// With Hide when off, only the keys that are on show, and the widget hides
// while none is; without it, every shown key always shows, a key that's
// off dimmed in the inactive color. The active color while any is on,
// else the inactive one. Hidden where no keyboard has the LEDs to read.
// Hovering lists each shown key as on or off. Drawn one box per key
// (Boxes: One per item), each box is its key's icon and short name, in
// its own on or off color.
BarIconWidget {
  id: root

  Component.onCompleted: LockKeysManager.acquire(root)
  Component.onDestruction: LockKeysManager.release(root)

  // The keys it shows, from its settings alone (the Repeater's model): its
  // one key in a box of its own
  readonly property var keys: root.box !== "" ? [root.box] : [...(properties.showCaps ? ["caps"] : []), ...(properties.showNum ? ["num"] : []), ...(properties.showScroll ? ["scroll"] : [])]
  readonly property var _glyphs: ({
      "caps": "keyboard_capslock",
      "num": "dialpad",
      "scroll": "swap_vert"
    })

  function isOn(key: string): bool {
    return key === "caps" ? LockKeysManager.capsLock : key === "num" ? LockKeysManager.numLock : LockKeysManager.scrollLock;
  }
  // A key's short name, its label in a box of its own
  function shortName(key: string): string {
    return key === "caps" ? I18n.tr("Caps") : key === "num" ? I18n.tr("Num") : I18n.tr("Scroll");
  }
  function keyName(key: string): string {
    return key === "caps" ? I18n.tr("Caps Lock") : key === "num" ? I18n.tr("Num Lock") : I18n.tr("Scroll Lock");
  }

  readonly property bool anyOn: keys.some(k => root.isOn(k))

  hidden: !LockKeysManager.available || keys.length === 0 || (properties.hideWhenOff && !anyOn)

  // A box of its own: its key's icon and name, which split; else the keys'
  // glyphs in its lead slot
  readonly property bool _single: root.box !== ""
  icon: root._single ? root._glyphs[root.box] ?? "" : ""
  text: root._single ? root.shortName(root.box) : ""
  showIcon: root._single
  showText: root._single
  leadLength: root._single ? 0 : root.isVertical ? glyphs.implicitHeight : glyphs.implicitWidth

  accentField: anyOn ? "activeColor" : "inactiveColor"
  // What an off key draws in: the inactive color's as drawn here (the
  // gradient's, where it gives way), whatever the others, so a key turning
  // on never tints the ones still off
  readonly property color _offColor: root.contentColor(root.drawnColor("inactiveColor"), "icon")

  Grid {
    id: glyphs
    parent: root.lead
    visible: !root._single
    anchors.centerIn: parent
    columns: root.isVertical ? 1 : root.keys.length
    spacing: root.barConfig.innerGap

    Repeater {
      model: root.keys

      StyledIcon {
        required property string modelData
        readonly property bool on: root.isOn(modelData)

        visible: on || !root.properties.hideWhenOff
        opacity: on ? 1 : 0.4
        text: root._glyphs[modelData]
        textColor: on ? root.iconColor : root._offColor
        textSize: root.fontSize * root.iconScale

        ColorGlide on color {}
      }
    }
  }

  // Each shown key, on or off, on the bar's inner side
  BarToolTip {
    widget: root
    shown: !root.hidden
    text: root.keys.map(k => root.isOn(k) ? I18n.tr("{0}: on", root.keyName(k)) : I18n.tr("{0}: off", root.keyName(k))).join("\n")
  }
}
