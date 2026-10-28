pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.hosts.popout

// A screen's dim background for full-screen surfaces (the overlay,
// workspace overview, launcher, power menu, onboarding; BackdropRequest):
// the whole monitor, under the bars and the border, which stay drawn over
// it. Its place in the stack (LayerStack: before the bars and border) is
// kept by mapping before them: Hyprland's layer rule orders it there
// whenever it maps; elsewhere it stays mapped, a pixel in the corner while
// nothing asks for it (LayerSlot.held). It takes no input: clicks go to
// the surface above it, or to the bars and border (which clears the
// surface's focus grab, unless the surface lets its screen's bars
// through: see SurfaceManager.grabPartners). Without a native focus grab it
// catches the click outside a grabbing surface instead, covering its
// screen while one is active (BackdropManager.catching).
PanelWindow {
  id: root

  // What it shows: the request shown last on its screen, or the one it
  // showed last while it goes
  readonly property var request: BackdropManager.requestOn(root.screen?.name ?? "")
  readonly property bool shown: root.request !== null
  property LastFound _last: LastFound {
    source: root.request
  }
  readonly property var _style: root._last.value ?? ({
      "slide": "",
      "fillColor": "transparent",
      "fillOpacity": 0
    })
  readonly property bool slide: root._style.slide !== ""
  // Where it waits while hidden, sliding: off the edge it comes from
  readonly property real _hiddenY: root._style.slide === "bottom" ? root._span : -root._span
  readonly property int duration: root.slide ? Appearance.animSlow : Appearance.animNormal

  // Whether it's showing or animating out
  readonly property bool _wanted: root.shown || (root.slide ? slideOffset.y !== root._hiddenY : fill.opacity > 0)
  readonly property real _span: root.screen?.height ?? root.height

  visible: slot.shown
  LayerSlot {
    id: slot
    window: root
    namespace: "axiom-backdrop"
    wanted: root._wanted || BackdropManager.catching
    held: true
  }

  anchors {
    left: true
    top: true
    right: !slot.idle
    bottom: !slot.idle
  }
  implicitWidth: 1
  implicitHeight: 1
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "axiom-backdrop"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  color: "transparent"
  mask: BackdropManager.catching ? null : root._noInput
  property Region _noInput: Region {}

  MouseArea {
    anchors.fill: parent
    enabled: BackdropManager.catching
    onPressed: BackdropManager.clickedOutside()
  }

  // Where the compositor blurs only what a window asks: the dim, as it
  // slides, while backdrops blur (LayerStack.blurBackdrops)
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.backdropRegionsOn(root.screen) ? fillBlur : null)
  BoxBlurRegion {
    id: fillBlur
    target: fill
    moving: slideOffset.y
    opacity: fill.opacity
    alpha: fill.color.a
    threshold: 0.01
  }

  Rectangle {
    id: fill
    anchors.fill: parent
    visible: !slot.idle
    color: root._style.fillColor
    // Sliding, it stays dim until it's out of sight, then clears so a
    // fading one after it fades in from nothing
    opacity: root.shown || (root.slide && slideOffset.y !== root._hiddenY) ? root._style.fillOpacity : 0

    Behavior on opacity {
      enabled: !root.slide
      NumberAnimation {
        duration: root.duration
        easing.type: Appearance.easing
      }
    }

    transform: Translate {
      id: slideOffset
      y: !root.slide || root.shown ? 0 : root._hiddenY
      Behavior on y {
        enabled: root.slide
        NumberAnimation {
          duration: root.duration
          easing.type: Easing.InOutQuad
        }
      }
    }
  }
}
