pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.reusable

/**
 * A popout that floats on the screen instead of growing out of an edge
 * (EdgePopout): a plain rounded box in an Overlay-layer window covering the
 * area the bars and border leave free, fading and scaling in. Used by the
 * detached launcher and the window switcher.
 *
 * Open/close/queue state and hover-loss dismissal come from
 * PopoutWrapperBase, as for EdgePopout, and its place among the popouts
 * from a PopoutClaim (`claimKey`), and the content is a Component in
 * the same way: loaded while open (unless keepLoaded), optionally exposing
 * `autoDismiss` / `dismissDelay` / `hovered`.
 *
 * Placement: the box's anchor point is `xFraction` across and `yFraction`
 * down the free area inside its margins (`margin`, or one per side), with
 * `xAlign`/`yAlign` saying which part of the box sits there (0 its
 * left/top, 0.5 its centre, 1 its right/bottom), and kept inside them. A
 * fraction equal to its align spreads the room left over: 0 against one
 * side, 0.5 centred, 1 against the other.
 * Content that changes height while open sets `maxContentHeight`: the box
 * is placed as if it were that tall, so it doesn't move, and grows down
 * from its top (or up from its bottom with `growUp`).
 */
PopoutWrapperBase {
  id: root

  required property ShellScreen screen

  property Component content: null
  readonly property Item contentItem: loader.item as Item
  // Keep content alive while closed (content that itself reports when the
  // popout should open)
  property bool keepLoaded: false

  property real xFraction: 0.5
  property real yFraction: 0.5
  property real xAlign: 0.5
  property real yAlign: 0.5
  property real margin: Appearance.screenMargin
  property real leftMargin: root.margin
  property real topMargin: root.margin
  property real rightMargin: root.margin
  property real bottomMargin: root.margin
  property real maxContentHeight: 0
  // The box glides to the content's height; off for content that animates
  // its own (the launcher's list), which the box then follows as is
  property bool animateHeight: true
  property bool growUp: false

  // Space between the box and its content
  property real contentPadding: Appearance.borderWidth + PopoutsConfig.padding
  property color fillColor: Theme.background
  property color strokeColor: Theme.foreground
  // Scale it grows in from
  property real closedScale: 0.95

  property string layerNamespace: "axiom-floating-popout"
  // Takes the keyboard, with a focus grab (content with a text field)
  property bool wantsKeyboardFocus: false
  // A click off the box closes it (the whole window takes input then)
  property bool closeOnClickOutside: false
  // Off leaves the focus grab to another window (see SurfaceGroup)
  property bool grabEnabled: true
  // Other windows the grab lets input through to
  property var grabWindows: []
  window: surfaceWindow

  currentItem: root.contentItem
  keepAlive: boxHover.hovered || (focusGrab.active && root.wantsKeyboardFocus)

  // Its place among the popouts (PopoutManager), under `claimKey` (none:
  // it takes no part): it shows once granted, closing what it covers below
  // it, and closes when a higher popout covers it (or won't open under one)
  property string claimKey: ""
  property string claimKind: "launcher"
  // Granted (or closing after it was, PopoutClaim.held)
  readonly property bool claimed: root.claimKey === "" || root.claim.held
  readonly property bool _showing: root.isOpen && root.claimed
  property PopoutClaim claim: PopoutClaim {
    key: root.claimKey
    kind: root.claimKind
    screen: root.screen?.name ?? ""
    occupied: root.occupied
    closing: root.isClosing
    // Once its window's place is known (LayerOrigin.settled)
    wanted: root.claimKey !== "" && root.isOpen && root.contentItem !== null && placeOnScreen.settled
    // The box where it's placed (as tall as it's placed by), on screen
    footprint: PopoutGeometry.offset([Qt.rect(box.x, box.placedY, box.width, box.placedHeight)], placeOnScreen.placed)
    onEvicted: root.hide()
    onRefused: root.hide()
  }

  PanelWindow {
    id: surfaceWindow
    screen: root.screen
    color: "transparent"
    // Stays mapped while the box fades out
    visible: root.occupied || box.opacity > 0
    focusable: root.wantsKeyboardFocus

    // Normal exclusion with no zone of its own: the window covers the area
    // the bars and border leave free
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.keyboardFocus: root.wantsKeyboardFocus ? (focusGrab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Only the box takes input, unless a click beside it closes it
    mask: Region {
      item: root.closeOnClickOutside ? surfaceWindow.contentItem : box
    }

    // Where the compositor blurs only what a window asks: the box, as it
    // scales open
    // (attached only there: attached at all, it claims the window's blur, and
    // Hyprland's layer rules no longer blur it)
    Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) ? boxBlur : null)
    // Where the window is on screen, for its claim's footprint
    LayerOrigin {
      id: placeOnScreen
      window: surfaceWindow
      namespace: root.layerNamespace
      layer: WlrLayer.Overlay
    }

    BoxBlurRegion {
      id: boxBlur
      target: box
      opacity: box.opacity
    }

    FocusGrab {
      id: focusGrab
      windows: [surfaceWindow].concat(root.grabWindows, SurfaceManager.modalWindows)
      active: root.isOpen && root.grabEnabled && (root.wantsKeyboardFocus || root.closeOnClickOutside)

      onActiveChanged: {
        if (active)
          root.contentItem?.forceActiveFocus();
      }

      onCleared: {
        if (!active)
          root.hide();
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.closeOnClickOutside
      onClicked: root.hide()
    }

    // The box's shadow (SurfaceShadow), cast by a copy of its shape
    // behind it, so the content isn't drawn through a layer. Only what
    // falls outside the box is kept, so none shows through a translucent one.
    // Not OutsideShadow: its capture drops the target's own transform, and
    // this copy scales with the box as it opens.
    Rectangle {
      visible: BarStyle.shadowed
      x: box.x
      y: box.y
      width: box.width
      height: box.height
      radius: box.radius
      color: "black"
      opacity: box.opacity
      scale: box.scale
      transformOrigin: box.transformOrigin
      layer.enabled: BarStyle.shadowed
      layer.effect: SurfaceShadow {
        cut: true
      }
    }

    Rectangle {
      id: box

      readonly property real contentHeight: root.contentItem?.implicitHeight ?? 0
      // The height it's placed by
      readonly property real placedHeight: Math.max(box.height, root.maxContentHeight + root.contentPadding * 2)
      // The room inside the margins
      readonly property real roomWidth: surfaceWindow.width - root.leftMargin - root.rightMargin
      readonly property real roomHeight: surfaceWindow.height - root.topMargin - root.bottomMargin
      readonly property real placedY: root.topMargin + Math.max(0, Math.min(box.roomHeight * root.yFraction - box.placedHeight * root.yAlign, box.roomHeight - box.placedHeight))

      width: (root.contentItem?.implicitWidth ?? 0) + root.contentPadding * 2
      height: box.contentHeight + root.contentPadding * 2
      x: root.leftMargin + Math.max(0, Math.min(box.roomWidth * root.xFraction - width * root.xAlign, box.roomWidth - width))
      y: root.growUp ? box.placedY + box.placedHeight - box.height : box.placedY
      color: BlurManager.fillOn(root.fillColor, root.screen)
      border.color: root.strokeColor
      border.width: Appearance.borderWidth
      radius: Appearance.borderRadius
      clip: true

      opacity: root._showing ? 1 : 0
      scale: root._showing ? 1 : root.closedScale
      transformOrigin: root.growUp ? Item.Bottom : root.maxContentHeight > 0 ? Item.Top : Item.Center
      Glide on opacity {
        duration: Appearance.animNormal
      }
      Glide on scale {
        duration: Appearance.animNormal
      }
      Glide on height {
        enabled: root.animateHeight
      }

      HoverHandler {
        id: boxHover
      }

      // Swallows clicks, so they don't reach the close-on-click area
      MouseArea {
        anchors.fill: parent
      }

      Loader {
        id: loader
        // Growing up, it hangs from the box's bottom: the box's height
        // animates, and the content must not move with it
        x: root.contentPadding
        y: root.growUp ? box.height - root.contentPadding - height : root.contentPadding
        width: root.contentItem?.implicitWidth ?? 0
        height: box.contentHeight
        active: root.occupied || root.keepLoaded
        sourceComponent: root.content

        onLoaded: root.updateDismissTimer()
      }
    }
  }
}
