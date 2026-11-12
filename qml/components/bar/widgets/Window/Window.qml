pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.services.system
import qs.components.bar.widgets.base

// The Window bar widget: the focused window's title. Sized to the title,
// shrinking (the label elides) down to just the icon when the bar is
// crowded, as Media does; `layout.maxSize` caps it. Its display style scrolls
// it (ticker) or puts it over the app (stacked). `appIcon` shows the
// window's app icon in the icon's place.
BarWidget {
  id: root

  readonly property var focused: ToplevelManager.activeToplevel
  icon: properties.icon
  // With no window focused, its icon
  iconSource: properties.appIcon && focused ? AppIconManager.resolveWindowIcon(focused.appId, focused.title) : ""
  text: root.focused?.title || properties.emptyText
  subtext: root.focused?.appId ?? ""
  // A title is any app's: never styled text or a remote image
  textFormat: Text.PlainText
}
