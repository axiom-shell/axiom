pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.ui

// The card every modal draws (the prompt, the power menu, the monitor
// prompt, the screen-share picker): a page-tone Surface that fades and slides
// in by Style.enterOffset (never a scale: scaled text goes soft), swallows
// clicks so they don't reach the dimmed screen behind it, and pads its
// content by `padding`. Children go in `body`, inset by it; the host sets the
// card's width and height from `padding` and its content's implicit size.
// `asking` draws the accent border (a question waiting for an answer). Give
// it the `window` it sits in and the window is a modal while it exists:
// every focus grab lets input through to it (SurfaceManager.registerModal).
// `blur` is the card's blur region (following `opacity` and `reveal`), for
// a window to hand to BackgroundEffect.blurRegion where the compositor
// blurs only what a window asks (attached only there: attached at all, it
// claims the window's blur, and Hyprland's layer rules no longer blur it).
Surface {
  id: root

  // -- Public API --
  // Shown: faded and slid in
  property bool shown: false
  // The accent border
  property bool asking: false
  // The window the card sits in, to register as a modal; none = not one
  property var window: null
  readonly property int padding: Style.space5
  // 0 → 1 while it slides in (a blur region's `moving`)
  property real reveal: root.shown ? 1 : 0
  // The card as a blur region
  readonly property BoxBlurRegion blur: BoxBlurRegion {
    target: root
    opacity: root.opacity
    moving: root.reveal
  }
  // Where the content goes, inset by `padding`
  default property alias slot: body.data

  // -- Implementation --
  tone: "page"
  border.color: root.asking ? Style.accent : Style.borderSubtle
  opacity: root.shown ? 1 : 0

  transform: Translate {
    y: Math.round((1 - root.reveal) * Style.enterOffset)
  }
  Glide on opacity {
    duration: Appearance.animNormal
  }
  Glide on reveal {
    duration: Appearance.animNormal
  }

  onWindowChanged: {
    if (root.window)
      SurfaceManager.registerModal(root.window);
  }
  Component.onCompleted: {
    if (root.window)
      SurfaceManager.registerModal(root.window);
  }
  Component.onDestruction: {
    if (root.window)
      SurfaceManager.unregisterModal(root.window);
  }

  // A click on the card is the card's, never the outside's
  MouseArea {
    anchors.fill: parent
  }

  Item {
    id: body
    x: root.padding
    y: root.padding
    width: root.width - root.padding * 2
    height: root.height - root.padding * 2
  }
}
