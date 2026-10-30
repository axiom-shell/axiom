pragma ComponentBehavior: Bound

import Quickshell.Wayland
import qs.components.bar.widgets.base

// The Window bar widget: the focused window's title. Sized to the title,
// shrinking (the label elides) down to just the icon when the bar is
// crowded, as Media does; `layout.size` caps it. Its display style scrolls
// it (ticker) or puts it over the app (stacked).
ValueStyleWidget {
  id: root

  readonly property string sizePolicy: "elastic"
  readonly property real minimumSize: root.iconLength + root.padding * 2

  icon: properties.icon
  text: ToplevelManager.activeToplevel?.title || properties.emptyText
  subtext: ToplevelManager.activeToplevel?.appId ?? ""
}
