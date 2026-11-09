pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The notification list's swipe-away, declared in the card or entry it
// moves (its parent, which takes `transform: swipe.shift`): it fades in
// dropping 8 px once built; dragged sideways it follows, fading over twice
// swipeThreshold, and let go past that it fires `swiped`, else snaps back.
// slideOut(delay) slides it the width the way it went and fades it, then
// fires `out`.
DragHandler {
  id: root

  property real swipeThreshold: 120
  readonly property Item host: root.parent
  readonly property Translate shift: Translate {}

  signal swiped
  signal out

  function slideOut(delay) {
    if (slide.running)
      return;
    pause.duration = delay;
    slide.start();
  }

  target: null
  yAxis.enabled: false
  Component.onCompleted: appear.start()

  onTranslationChanged: {
    if (!active || slide.running)
      return;
    root.shift.x = translation.x;
    root.host.opacity = 1 - Math.min(1, Math.abs(translation.x) / (root.swipeThreshold * 2));
  }
  onActiveChanged: {
    if (active || slide.running)
      return;
    if (Math.abs(root.shift.x) > root.swipeThreshold)
      root.swiped();
    else
      snapBack.start();
  }

  readonly property Animation _appear: ParallelAnimation {
    id: appear
    NumberAnimation {
      target: root.host
      property: "opacity"
      from: 0
      to: 1
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root.shift
      property: "y"
      from: -8
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  // A swipe short of the threshold: slide back and undo the fade
  readonly property Animation _snapBack: ParallelAnimation {
    id: snapBack
    NumberAnimation {
      target: root.shift
      property: "x"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root.host
      property: "opacity"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  readonly property Animation _slide: SequentialAnimation {
    id: slide
    PauseAnimation {
      id: pause
    }
    ParallelAnimation {
      NumberAnimation {
        target: root.shift
        property: "x"
        to: root.shift.x < 0 ? -root.host.width : root.host.width
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
      NumberAnimation {
        target: root.host
        property: "opacity"
        to: 0
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
    }
    ScriptAction {
      script: root.out()
    }
  }
}
