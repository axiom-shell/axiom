pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.ui

// A full-screen surface's dim background on its screen, shown while
// `shown`: drawn by that screen's backdrop window (ScreenBackdrop,
// through BackdropManager), under the bars and the border.
QtObject {
  id: root

  property ShellScreen screen: null
  property bool shown: false
  // Slides in with the surface (the overlay) from that edge, "top" or
  // "bottom", instead of fading in and out ("")
  property string slide: ""
  property color fillColor: Appearance.darkMode ? Theme.background : Theme.foreground
  property real fillOpacity: 0.85

  property int _uid: 0
  readonly property var _request: root.screen ? {
    "screen": root.screen.name,
    "shown": root.shown,
    "slide": root.slide,
    "fillColor": root.fillColor,
    "fillOpacity": root.fillOpacity
  } : null
  on_RequestChanged: {
    if (root._uid > 0)
      BackdropManager.update(root._uid, root._request);
  }
  Component.onCompleted: {
    root._uid = BackdropManager.register();
    BackdropManager.update(root._uid, root._request);
  }
  Component.onDestruction: BackdropManager.update(root._uid, null)
}
