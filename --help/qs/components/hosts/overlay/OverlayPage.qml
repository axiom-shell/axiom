pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One page of the overlay: shown when it's the current page, sliding in
// from the side the navigation came from (`direction`), while the page it
// replaces slides out the other way and fades. The content is only
// instantiated while `loaded` (or still leaving).
Item {
  id: root

  required property int pageIndex
  required property int currentIndex
  required property int direction
  required property bool loaded
  default property Component content

  readonly property bool current: root.currentIndex === root.pageIndex
  // Still on screen, sliding out after another page took its place
  property bool _leaving: false
  readonly property real _shift: Math.max(Widget.spacing * 3, Math.round(root.width * 0.06))

  anchors.centerIn: parent
  implicitWidth: contentLoader.item ? contentLoader.item.implicitWidth : 0
  implicitHeight: contentLoader.item ? contentLoader.item.implicitHeight : 0
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

  Loader {
    id: contentLoader
    anchors.centerIn: parent
    active: false
    sourceComponent: root.content
    onLoaded: console.log(`Overlay page ${root.pageIndex} built in ${Date.now() - root._started} ms`)
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
