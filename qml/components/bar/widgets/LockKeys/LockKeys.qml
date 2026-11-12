pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.bar.widgets.base

// Caps Lock, Num Lock and Scroll Lock (those its settings show), from
// LockKeysManager (the keyboards' LEDs), a glyph each as BarWidget's
// segments. With Hide when off, only the keys that are on show, and the
// widget hides while none is; without it, every shown key always shows, a
// key that's off in a muted color. The active color while any is on, else
// the inactive one; a key whose state differs from the widget's reads in
// its own field. Hidden where no keyboard has the LEDs to read. Hovering
// lists each shown key as on or off. Drawn one box per key (Boxes: One per
// item), each box is its key's icon and short name.
BarWidget {
  id: root

  Component.onCompleted: LockKeysManager.acquire(root)
  Component.onDestruction: LockKeysManager.release(root)

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

  // The keys its settings show
  items: ["caps", "num", "scroll"].filter(k => root.properties[{
        "caps": "showCaps",
        "num": "showNum",
        "scroll": "showScroll"
      }[k]])
  readonly property bool anyOn: root.shownItems.some(k => root.isOn(k))

  hidden: !LockKeysManager.available || root.shownItems.length === 0 || (root.properties.hideWhenOff && !root.anyOn)
  accentField: root.anyOn ? "activeColor" : "inactiveColor"
  // A key that's off is muted; one of the other state than the widget's
  // reads in its own field (the widget's colors are already its field's)
  segmentData: key => ({
        "icon": root._glyphs[key],
        "text": root.ownBox ? root.shortName(key) : "",
        "field": root.isOn(key) === root.anyOn ? "" : "inactiveColor",
        "muted": !root.isOn(key),
        "hidden": !root.isOn(key) && root.properties.hideWhenOff,
        "small": false
      })

  // Each shown key, on or off, on the bar's inner side
  BarToolTip {
    widget: root
    shown: !root.hidden
    text: root.shownItems.map(k => root.isOn(k) ? I18n.tr("{0}: on", root.keyName(k)) : I18n.tr("{0}: off", root.keyName(k))).join("\n")
  }
}
