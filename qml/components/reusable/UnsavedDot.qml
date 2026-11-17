pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The dot beside something with unsaved edits (a settings category, card
// or field; a bar, page or edge menu in its editor). `tone` is the fill it
// sits on ("", "accentContainer" for a selected row, "accent" for the current
// tab). Pops in and out by `shown`.
PopInRectangle {
  id: root

  property string tone: ""

  implicitWidth: Widget.px(8)
  implicitHeight: Widget.px(8)
  radius: width / 2
  color: root.tone === "" ? Style.accent : Style.inkOf(root.tone).accent
}
