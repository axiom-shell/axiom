pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.components.bar.widgets.base

// The Window bar widget: the focused window's title. Sized to the title,
// shrinking (the label elides) down to just the icon when the bar is
// crowded, as Media does; `layout.maxSize` caps it. Its display style scrolls
// it (ticker) or puts it over the app (stacked).
ValueStyleWidget {
  id: root

  icon: properties.icon
  text: ToplevelManager.activeToplevel?.title || properties.emptyText
  subtext: ToplevelManager.activeToplevel?.appId ?? ""
  // A title is any app's: never styled text or a remote image
  textFormat: Text.PlainText
}
