pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// An icon saying what it means in a tooltip on hover (`tip`; none while
// it's empty): a flag or a problem shown without its text beside it
StyledIcon {
  id: root

  property string tip: ""
  // Wraps the tooltip at this width while above 0
  property real tipWidth: 0
  readonly property bool hovered: hover.hovered

  HoverHandler {
    id: hover
    enabled: root.tip !== ""
  }

  LazyLoader {
    active: hover.hovered
    StyledToolTip {
      target: root
      text: root.tip
      maxWidth: root.tipWidth
    }
  }
}
