pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.compositor
import qs.components.content.parts
import qs.components.surfaces.screenlayout
import qs.services.ui

// What one screen shows while the built-in lock is up (the content of a
// WlSessionLockSurface, see shell/Lockscreen.qml), or in the layouts
// editor's preview: the layout's background and modules (ScreenLayoutView).
// The compositor gives the lock surfaces all input and hides everything
// else, so this needs no focus grabs or layer tricks.
//
// The password field lives on the target screen (a Password module, else
// a field of its own, so no layout can lock anyone out); other screens show
// the modules without it, or the background only (`otherScreens`). Nothing
// here may unlock or run commands: only AuthManager's success unlocks, and
// lock screen modules are the ones whose x-hosts list "lockscreen".
ScreenLayoutView {
  id: root

  // The editor's preview: nothing is locked and the field is inert
  property bool preview: false

  readonly property bool isTarget: ShellManager.isTarget(root.screen)
  readonly property var allModules: root.layout?.modules ?? []
  // Where this surface's Password module reports itself
  // (SurfaceManager.requiredFields): this instance's own, set once on
  // creation (a binding would loop on the counter newSurfaceKey bumps)
  property string passwordKey: ""

  // The layout shown: the saved one, or the layouts editor's draft in its
  // preview (see LockscreenConfig.layout)
  layout: LockscreenConfig.layout
  modules: root.isTarget ? root.allModules : root.layout?.otherScreens === "layout" ? root.allModules.filter(module => module?.type !== "Password") : []
  wallpaper: root.screen ? ThemeManager.wallpaperFor(root.screen.name) : ""
  hyprBlur: CompositorManager.blur
  host: ({
      "kind": "lockscreen",
      "target": root.isTarget,
      "preview": root.preview,
      "key": root.passwordKey,
      "bare": !(root.layout?.moduleBorders ?? false),
      "passwordBorder": root.layout?.borders?.password ?? false,
      "greetingBorder": root.layout?.borders?.greeting ?? false
    })

  // The fallback field waits a tick, so a Password module can report first
  property bool _settled: false
  Component.onCompleted: {
    root.passwordKey = SurfaceManager.newSurfaceKey(root.preview ? "preview" : "lock");
    Qt.callLater(() => root._settled = true);
  }

  // No Password module shows on the target screen: a field of its own,
  // over whatever else is there, near the bottom
  Loader {
    z: 1
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: parent.height / 6
    width: Math.min(parent.width * 0.6, Appearance.fontSize * 28)
    active: root.isTarget && root._settled && SurfaceManager.requiredFields[root.passwordKey] !== true
    sourceComponent: Rectangle {
      implicitHeight: fallback.implicitHeight + Widget.padding * 2
      radius: Widget.radius
      color: Theme.background
      border.color: Theme.border
      border.width: Appearance.borderWidth

      PasswordField {
        id: fallback
        anchors.fill: parent
        anchors.margins: Widget.padding
        active: !root.preview
      }
    }
  }
}
