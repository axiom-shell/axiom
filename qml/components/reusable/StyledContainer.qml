pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// A themed box: background through the surface opacity (or solid),
// optional border and radius. The base of the text fields and form rows.
Rectangle {
  id: root

  // -- Configurable Appearance --
  property color backgroundColor: Style.surfaceSunken
  property alias borderColor: root.border.color
  property alias borderWidth: root.border.width
  property alias borderRadius: root.radius
  // Filled solid, whatever the surface opacity
  property bool solid: false

  // -- Implementation --
  color: Style.edgeFill(root.backgroundColor, root.solid)
  border.color: "transparent"
  border.width: Style.hairline
  radius: Style.radius
}
