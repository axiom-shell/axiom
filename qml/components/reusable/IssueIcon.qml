pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config

// A problem's icon, as IssueList draws it (error red, warning amber, info
// accent), saying what's wrong in a tooltip on hover (`tip`; none while
// it's empty, as beside a line that already says it)
StyledIcon {
  id: root

  // "error" | "warning" | "info"
  property string level: "warning"
  property string tip: ""
  // The level's color (`textColor` unless a host sets its own)
  readonly property color tone: root.level === "error" ? Theme.error : root.level === "info" ? Theme.accent : Theme.warning

  text: root.level === "error" ? "error" : root.level === "info" ? "info" : "warning"
  textColor: root.tone

  HoverHandler {
    id: hover
    enabled: root.tip !== ""
  }

  LazyLoader {
    active: hover.hovered
    StyledToolTip {
      target: root
      text: root.tip
    }
  }
}
