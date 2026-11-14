pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A divider line, `Style.dividerWidth` thick, in the divider colour of the
// fill it is drawn on (`backTone`, the tone of that Surface; menus,
// dropdowns and tooltips are `raised`)
Rectangle {
  id: root

  // -- Public API --
  // The tone of the fill it sits on
  property string backTone: "surface"
  // The stronger border colour
  property bool strong: false
  // The accent, where a divider is accent by design
  property bool accent: false

  // -- Configurable Appearance --
  property alias separatorColor: root.color
  property alias separatorHeight: root.height

  // -- Implementation --
  height: Style.dividerWidth
  color: root.accent ? Style.accent : root.strong ? Style.borderStrong : Style.inkOf(root.backTone).divider
  radius: Math.min(width, height) / 2
}
