pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One page of the overlay: its own card grid (`grid`, from its `sizing`) and
// PageBox, shown when it's the current page, sliding in from the side the
// navigation came from (`direction`), while the page it replaces slides out
// the other way and fades. The content is only instantiated while `loaded`
// (or still leaving). Its queued build jobs (StreamedLoaders, a module grid's
// modules) run only while it is current and the overlay open (`buildHeld`):
// a neighbour builds its frame and its cards when it arrives.
Item {
  id: root

  required property int pageIndex
  required property int currentIndex
  required property int direction
  required property bool loaded
  // The overlay is open (shown) on its screen
  required property bool overlayOpen
  // The overlay opened reduced (OverlayPanel.reduced): a page switch fades
  // only
  property bool reduced: false
  // The screen it's on and the drawn px the page may take (OverlayPages)
  required property var screen
  required property real roomWidth
  required property real roomHeight
  // Its view's own sizing, null for the global sizes alone
  property var sizing: null
  default property Component content

  // What the content sizes itself against
  readonly property OverlayGrid grid: pageGrid
  // The factor (at most 1) its PageBox shrinks it by, once its content is
  // built: undefined before and after (OverlayPages reports it)
  readonly property var fit: contentLoader.item ? pageBox.fitScale : undefined
  // The px the page takes as drawn, at its zoom and fit
  readonly property real drawnWidth: pageBox.width * pageBox.contentZoom
  readonly property real drawnHeight: pageBox.height * pageBox.contentZoom

  readonly property bool current: root.currentIndex === root.pageIndex
  // Its queued build jobs wait (BuildOrder.holderOf, BuildQueueManager)
  readonly property bool buildHeld: !(root.current && root.overlayOpen)
  // Still on screen, sliding out after another page took its place
  property bool _leaving: false
  readonly property real _shift: root.reduced ? 0 : Math.max(Widget.spacing * 3, Math.round(root.drawnWidth * 0.06))

  anchors.fill: parent
  visible: root.current || root._leaving
  opacity: root.current ? 1 : 0

  onCurrentChanged: {
    if (root.current) {
      slideOut.stop();
      root._leaving = false;
      slideIn.from = root._shift * root.direction;
      slideIn.restart();
    } else if (root.visible) {
      slideIn.stop();
      root._leaving = true;
      slideAway.to = -root._shift * root.direction;
      slideOut.restart();
    }
  }

  OverlayGrid {
    id: pageGrid
    screen: root.screen
    sizing: root.sizing
    availableWidth: root.roomWidth
    availableHeight: root.roomHeight
    drawnZoom: pageBox.contentZoom
  }

  PageBox {
    id: pageBox
    zoom: pageGrid.zoom
    roomWidth: root.roomWidth
    roomHeight: root.roomHeight
    width: contentLoader.item ? contentLoader.item.implicitWidth : 0
    height: contentLoader.item ? contentLoader.item.implicitHeight : 0
    onFitScaleChanged: if (root.current)
      console.log(`Overlay page ${root.pageIndex} scaled to ${pageBox.fitScale.toFixed(3)} (card unit ${pageGrid.unit} drawn at ${pageGrid.drawnUnit}, zoom ${pageGrid.zoom.toFixed(3)})`)

    Loader {
      id: contentLoader
      anchors.centerIn: parent
      active: false
      sourceComponent: root.content
      onLoaded: console.log(`Overlay page ${root.pageIndex} built in ${Date.now() - root._started} ms`)
    }
  }

  // Set from here, not bound, so the build can be timed (the Loader builds
  // before it notifies `active`), for scripts/dev/bench_overlay.sh
  readonly property bool _wanted: root.loaded || root._leaving
  property real _started: 0
  on_WantedChanged: root._activate()
  Component.onCompleted: root._activate()
  function _activate() {
    if (root._wanted === contentLoader.active)
      return;
    root._started = Date.now();
    contentLoader.active = root._wanted;
  }

  transform: Translate {
    id: slideTransform
  }

  Glide on opacity {
    duration: Appearance.animNormal
  }

  NumberAnimation {
    id: slideIn
    target: slideTransform
    property: "x"
    to: 0
    duration: Appearance.animNormal
    easing.type: Appearance.easing
  }

  SequentialAnimation {
    id: slideOut
    NumberAnimation {
      id: slideAway
      target: slideTransform
      property: "x"
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    ScriptAction {
      script: {
        root._leaving = false;
        slideTransform.x = 0;
      }
    }
  }
}
