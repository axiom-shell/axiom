pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable

// The top of the Workspaces card (the section's `x-intro`): where the
// compositor makes its workspaces itself (CompositorManager.
// dynamicWorkspaces), why the layout below is greyed out and what the
// workspace keys do instead. Not for the scrolling layout's, which are
// axiom's (dynamicByLayout): the layout applies there
ColumnLayout {
  id: root

  readonly property bool shown: CompositorManager.dynamicWorkspaces && !CompositorManager.dynamicByLayout

  spacing: Widget.spacing

  IssueList {
    issues: [
      {
        "level": "info",
        "text": I18n.tr("{0} makes and removes workspaces itself: each monitor has one column of them, with an empty one at the end. The layout below doesn't apply; up and down step through the column, left and right go to the next monitor.", CompositorManager.displayName)
      }
    ]
  }
}
