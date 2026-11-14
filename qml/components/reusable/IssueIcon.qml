pragma ComponentBehavior: Bound
import QtQuick

// A problem's icon, as IssueList draws it (error red, warning amber, info
// accent), saying what's wrong in a tooltip on hover (`tip`; none while
// it's empty, as beside a line that already says it)
TipIcon {
  id: root

  // "error" | "warning" | "info"
  property string level: "warning"

  text: root.level === "error" ? "error" : root.level === "info" ? "info" : "warning"
  // The level's tone name (the inherited StyledText.tone), which IssueList's
  // text beside it takes too
  tone: root.level === "error" ? "error" : root.level === "info" ? "accent" : "warning"
}
