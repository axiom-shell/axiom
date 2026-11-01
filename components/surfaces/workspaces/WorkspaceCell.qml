pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

import qs.config
import qs.components.methods
import qs.components.reusable

// One workspace on the overview board: a miniature desktop (the monitor's
// wallpaper, or a plain color). Its number is a WorkspaceNumber, drawn above
// the windows by OverviewGrid. Visual only; OverviewInput takes the input.
Item {
  id: root

  // A wallpaper URL, or "" for a plain `color`
  property string wallpaper: ""
  property color color: Theme.backgroundAlt
  // 0-1: how dark it is drawn when it isn't the active workspace
  property real dim: 0.5
  property real radius: Widget.radius
  // The monitor's active workspace
  property bool current: false
  property bool hovered: false
  // A window is being dragged over it; dropFill: onto it as a whole (it
  // has no tiled windows to split)
  property bool dropTarget: false
  property bool dropFill: false

  ClippingRectangle {
    id: desktop
    anchors.fill: parent
    radius: root.radius
    color: root.color

    Image {
      anchors.fill: parent
      visible: root.wallpaper !== ""
      source: root.wallpaper
      // Every cell asks for the same size, so they share one decoded image
      sourceSize: Qt.size(Math.round(root.width), Math.round(root.height))
      fillMode: WallpaperFill.fillMode(Appearance.wallpaperFill)
      asynchronous: true
      cache: true
    }

    // Other workspaces sit back a little
    Rectangle {
      anchors.fill: parent
      color: Theme.base00
      opacity: root.current || root.dropTarget ? 0 : root.hovered ? root.dim * 0.4 : root.dim

      Glide on opacity {}
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: root.dropFill ? Qt.alpha(Theme.accent, 0.3) : "transparent"
    border.width: root.current || root.dropTarget ? Appearance.borderWidth * 2 : Appearance.borderWidth
    border.color: root.dropTarget ? Theme.accent : root.current ? Theme.accent : root.hovered ? Theme.borderFocus : Theme.border

    ColorGlide on border.color {}
  }
}
