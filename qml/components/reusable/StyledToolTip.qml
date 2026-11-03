pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui

// Hover tooltip in a popup window of its own, so it isn't clipped by the
// small layer windows (bars, popouts) buttons live in. Appears after a
// short delay once created; create it only while hovered, e.g.
//   LazyLoader { active: area.containsMouse && tip !== ""; StyledToolTip { target: button; text: tip } }
PopupWindow {
  id: root

  required property Item target
  property string text: ""
  // Side of the target to show on
  property int edges: Edges.Bottom

  property bool _delayed: false

  visible: root._delayed && root.text !== "" && !SurfaceManager.captureFrozen
  color: "transparent"
  implicitWidth: box.implicitWidth
  implicitHeight: box.implicitHeight

  anchor.item: root.target
  anchor.edges: root.edges
  anchor.gravity: root.edges
  anchor.margins.top: root.edges === Edges.Bottom ? Widget.spacing : 0
  anchor.margins.bottom: root.edges === Edges.Top ? Widget.spacing : 0
  anchor.margins.left: root.edges === Edges.Right ? Widget.spacing : 0
  anchor.margins.right: root.edges === Edges.Left ? Widget.spacing : 0

  Timer {
    interval: 500
    running: true
    onTriggered: root._delayed = true
  }

  // Where the compositor blurs only what a window asks: the box, as
  // Hyprland blurs layers' popups
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) ? boxBlur : null)
  BoxBlurRegion {
    id: boxBlur
    target: box
    opacity: box.opacity
  }

  StyledContainer {
    id: box
    anchors.fill: parent
    implicitWidth: label.implicitWidth + Widget.padding * 2
    implicitHeight: label.implicitHeight + Widget.spacing * 2
    backgroundColor: Theme.background
    borderColor: Theme.border
    // Fades in as the window appears
    opacity: root.visible ? 1 : 0

    Glide on opacity {}

    StyledText {
      id: label
      anchors.centerIn: parent
      text: root.text
    }
  }
}
