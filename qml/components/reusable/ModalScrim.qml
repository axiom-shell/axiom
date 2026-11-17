pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The dimmed screen behind a modal card (the prompt, the screen-share
// picker): Style.scrim, faded with `shown`, over the whole window. `blur` is
// its blur region, for a window to hand to BackgroundEffect.blurRegion where
// the compositor blurs only what a window asks (attached only there:
// attached at all, it claims the window's blur, and Hyprland's layer rules no
// longer blur it). Children (a click area) go inside it.
Rectangle {
  id: root

  property bool shown: false
  readonly property BoxBlurRegion blur: blurRegion

  anchors.fill: parent
  color: Style.scrim
  opacity: root.shown ? 1 : 0

  Glide on opacity {
    duration: Appearance.animNormal
  }

  BoxBlurRegion {
    id: blurRegion
    target: root
    opacity: root.opacity
    alpha: root.color.a
    threshold: 0.01
  }
}
