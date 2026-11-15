pragma ComponentBehavior: Bound
import QtQuick

// The box of something that drops down over other content (a picker, a
// list opened from a header): a raised, outlined Surface, solid with a soft
// shadow while `floating`
Surface {
  id: root

  // Over other content: solid, and casts a shadow
  property bool floating: true

  tone: "raised"
  solid: root.floating
  shadowed: root.floating
}
