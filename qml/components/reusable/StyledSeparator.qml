pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A divider line, `separatorHeight` thick (the border width), in the
// border color unless set
Rectangle {
  id: root

  // -- Configurable Appearance --
  property alias separatorColor: root.color
  property alias separatorHeight: root.height

  // -- Implementation --
  height: Appearance.borderWidth
  color: Theme.border
  radius: Math.min(width, height) / 2
}
