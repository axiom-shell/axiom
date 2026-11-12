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
  // Where the wallpaper image sits in the cell, { x, y, w, h } (the full
  // monitor's, so a cell cropped to the usable area shows the right part);
  // null fills the cell
  property var wallpaperRect: null
  property size wallpaperSize: Qt.size(0, 0)
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
  // A color for the borders and the drop fill (a scratchpad's); transparent
  // keeps the usual ones
  property color tint: "transparent"
  readonly property bool tinted: root.tint.a > 0

  ClippingRectangle {
    id: desktop
    anchors.fill: parent
    radius: root.radius
    color: root.color

    Image {
      x: root.wallpaperRect?.x ?? 0
      y: root.wallpaperRect?.y ?? 0
      width: root.wallpaperRect?.w ?? root.width
      height: root.wallpaperRect?.h ?? root.height
      visible: root.wallpaper !== ""
      source: root.wallpaper
      // Every cell asks for the same size, so they share one decoded image
      sourceSize: root.wallpaperSize.width > 0 ? root.wallpaperSize : Qt.size(Math.round(root.width), Math.round(root.height))
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
    color: root.dropFill ? Qt.alpha(root.tinted ? root.tint : Theme.accent, 0.3) : "transparent"
    border.width: root.current || root.dropTarget ? Appearance.borderWidth * 2 : Appearance.borderWidth
    border.color: root.tinted ? root.tint : root.dropTarget ? Theme.accent : root.current ? Theme.accent : root.hovered ? Theme.borderFocus : Theme.border

    ColorGlide on border.color {}
  }
}
