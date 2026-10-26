pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.components.content.parts
import qs.components.surfaces.screenlayout
import qs.services.ui

// What one screen of the greeter shows (greetd's login screen, run from
// greeter.qml), or the layouts editor's preview of it: the layout's
// background and modules (ScreenLayoutView).
//
// The login box lives on the target screen (Greeter.monitor: a Login
// module, else a box of its own, so no layout can keep anyone out); other
// screens show the modules without it, or the background only
// (`otherScreens`). Greeter modules are the ones whose x-hosts list
// "greeter".
ScreenLayoutView {
  id: root

  // The editor's preview: the box and every action are inert
  property bool preview: false

  // The preview shows on one screen, which is its target
  readonly property bool isTarget: root.preview || General.screensFor(GreeterConfig.screen)[0] === root.screen
  readonly property var allModules: root.layout?.modules ?? []
  // Where this surface's Login module reports itself
  // (ShellManager.requiredFields): set once on creation
  property string loginKey: ""

  // The layout shown: the saved one, or the layouts editor's draft in its
  // preview
  layout: GreeterConfig.layout
  modules: root.isTarget ? root.allModules : root.layout?.otherScreens === "layout" ? root.allModules.filter(module => module?.type !== "Login") : []
  wallpaper: ThemeManager.wallpaperFor(root.screen.name)
  // The login screen is solid (CompositorManager keeps the greeter's
  // surfaces opaque): no frosting, in the editor's preview either
  frost: false
  host: ({
      "kind": "greeter",
      "target": root.isTarget,
      "preview": root.preview,
      "key": root.loginKey,
      "bare": !(root.layout?.moduleBorders ?? false),
      "passwordBorder": root.layout?.borders?.password ?? false,
      "greetingBorder": root.layout?.borders?.greeting ?? false
    })

  // The fallback box waits a tick, so a Login module can report first
  property bool _settled: false
  Component.onCompleted: {
    root.loginKey = ShellManager.newSurfaceKey(root.preview ? "preview" : "greeter");
    Qt.callLater(() => root._settled = true);
  }

  // No Login module shows on the target screen: a box of its own, over
  // whatever else is there, near the bottom
  Loader {
    z: 1
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: parent.height / 6
    width: Math.min(parent.width * 0.6, Appearance.fontSize * 28)
    active: root.isTarget && root._settled && ShellManager.requiredFields[root.loginKey] !== true
    sourceComponent: Rectangle {
      implicitHeight: fallback.implicitHeight + Widget.padding * 2
      radius: Widget.radius
      color: Theme.background
      border.color: Theme.border
      border.width: Appearance.borderWidth

      LoginField {
        id: fallback
        anchors.fill: parent
        anchors.margins: Widget.padding
        active: !root.preview && Paths.greeter
      }
    }
  }
}
