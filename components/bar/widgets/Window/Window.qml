pragma ComponentBehavior: Bound

import Quickshell.Wayland
import qs.components.bar.widgets.base

// The Window bar widget: the focused window's title, elastic in width;
// its display style scrolls it (ticker) or puts it over the app (stacked).
ValueStyleWidget {
  id: root

  // Grows with the title up to preferredSize, and gives way when crowded
  readonly property string sizePolicy: "elastic"
  readonly property int preferredSize: 240
  readonly property int minimumSize: 80

  icon: properties.icon
  text: ToplevelManager.activeToplevel?.title || properties.emptyText
  subtext: ToplevelManager.activeToplevel?.appId ?? ""
}
