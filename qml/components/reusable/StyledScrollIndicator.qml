pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.config

// A scroll indicator drawn from Style (a bare ScrollIndicator draws in the
// user's Qt palette): a thin pill, faint at rest and muted while scrolling,
// fading with the shell's glide.
ScrollIndicator {
  id: root

  contentItem: Rectangle {
    implicitWidth: Widget.px(4)
    implicitHeight: Widget.px(4)
    // there is no Style.radiusPill: a pill's radius is its own half width
    radius: Math.min(width, height) / 2
    color: root.active ? Style.textMuted : Style.textFaint
    opacity: root.size < 1 ? 1 : 0

    Glide on opacity {}
    ColorGlide on color {}
  }
}
