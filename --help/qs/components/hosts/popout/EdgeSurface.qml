pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// An AttachedSurface growing out of a screen edge, wired from its
// EdgePlacement (`geometry`) and, for a host with submenus, its
// SubmenuHost: whether it's detached, runs straight off its edge, how its
// ends join or run flush, its backfill, who fills it (the blur window, or
// itself, solid while blur is paused for a fullscreen window), how it
// casts its shadow, what's left open in its strokes and shadow under a
// submenu, the corners a submenu squares, and its BlurShape. The same for bar popouts, edge
// popouts and docks: hosts set where it is, its box, `active`, colours and
// content.
AttachedSurface {
  id: root

  // Its EdgePlacement
  required property var geometry
  property var submenu: null
  // Its window's screen name and whether it shows, for its BlurShape
  property string screenName: ""
  property bool windowShown: false
  // Clipped there, in screen coordinates (BlurShape.clipRect)
  property var blurClip: null
  // Animate the corners a submenu squares (once the host has settled)
  property bool animateShape: false

  edge: root.geometry.edge
  castShadow: true
  connectorGap: root.geometry.connectorGap
  detached: root.geometry.detached
  straight: root.geometry.straight
  joinStart: root.geometry.place.joinStart
  joinEnd: root.geometry.place.joinEnd
  flushStart: root.geometry.place.flushStart
  flushEnd: root.geometry.place.flushEnd
  straightJoinStart: root.geometry.straightJoinStart
  straightJoinEnd: root.geometry.straightJoinEnd
  backfill: root.geometry.backfill

  backed: root.geometry.backed
  opaque: root.geometry.opaque
  shadowLook: root.geometry.shadowLook

  // Under a submenu: its opening in the box's side, the fillet where it
  // joins the bar side, and its box out of this one's shadow
  strokeHoles: root.submenu?.strokeHoles ?? []
  shadowHoles: root.submenu?.shadowHoles ?? []
  // ...where it runs flush to the box's end, carrying on a wall of it
  wallsRunOn: root.submenu?.shadowHoles ?? []
  // Square where a submenu runs flush to the box's end, or (a detached
  // box) its near corner
  readonly property var _side: root.submenu?.side ?? null
  startCornerRadius: root._side?.squareStartCorner ? 0 : root.cornerRadius
  endCornerRadius: root._side?.squareEndCorner ? 0 : root.cornerRadius
  startNearRadius: root._side?.squareStartNear ? 0 : Appearance.borderRadius
  endNearRadius: root._side?.squareEndNear ? 0 : Appearance.borderRadius
  Glide on startCornerRadius {
    enabled: root.animateShape
  }
  Glide on endCornerRadius {
    enabled: root.animateShape
  }
  Glide on startNearRadius {
    enabled: root.animateShape
  }
  Glide on endNearRadius {
    enabled: root.animateShape
  }
  // Joined at the bar side, the stroke its wall there ran flush into
  // carries on past it, under the submenu
  flushStartThrough: !((root.submenu?.sideJoined ?? false) && root.submenu.openToLeft)
  flushEndThrough: !((root.submenu?.sideJoined ?? false) && !root.submenu.openToLeft)

  BlurShape {
    source: root
    screen: root.screenName
    x: (root.geometry.origin?.x ?? 0) + root.x
    y: (root.geometry.origin?.y ?? 0) + root.y
    shown: root.backed && root.windowShown
    overlayLayer: root.geometry.onOverlayLayer
    clipRect: root.blurClip
  }
}
