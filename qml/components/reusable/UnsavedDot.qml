pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The dot beside something with unsaved edits (a settings category, card
// or field; a bar, page or edge menu in its editor). `onAccent` for a
// selected row, which is filled with the accent itself. Pops in and out
// by `shown`.
PopInRectangle {
  property bool onAccent: false

  implicitWidth: Widget.px(8)
  implicitHeight: Widget.px(8)
  radius: width / 2
  color: onAccent ? Theme.background : Theme.accent
}
