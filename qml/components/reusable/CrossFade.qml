pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Shows `value` through `delegate`, cross-fading when it changes: a new
// copy is made for the new value and fades in over the old one, which
// fades out and goes. For content that changes in place (a track's title
// and cover, a weather or volume icon), where a swap would snap.
//
// The delegate's root declares `required property var value`. A copy
// that isn't ready to show yet (an image still loading) can say so with a
// `ready` property: the old copy stays until it turns true. Copies fill
// this item, whose implicit size is the current copy's.
//
//   CrossFade {
//     value: MediaManager.trackTitle
//     delegate: StyledText {
//       required property var value
//       text: value
//     }
//   }
Item {
  id: root

  property var value
  property Component delegate

  // The copy shown (or fading in, or waiting to be ready), and the one
  // fading out
  property Item _current: null
  property Item _leaving: null
  // The current copy hasn't been shown yet (not ready)
  property bool _waiting: false

  implicitWidth: _current?.implicitWidth ?? 0
  implicitHeight: _current?.implicitHeight ?? 0

  // Not before it's complete: the delegate can land before the value
  property bool _built: false
  onValueChanged: _swap()
  onDelegateChanged: _swap()
  Component.onCompleted: {
    _built = true;
    _swap();
  }
  Component.onDestruction: {
    fadeIn.stop();
    fadeOut.stop();
  }

  function _swap() {
    if (!root._built || !root.delegate)
      return;
    const next = root.delegate.createObject(root, {
      "value": root.value,
      "opacity": 0
    });
    if (!next)
      return;
    next.width = Qt.binding(() => root.width);
    next.height = Qt.binding(() => root.height);

    // The latest value wins: a copy never shown is dropped (what's on
    // screen stays until the new one is ready); else the copy still
    // fading out goes at once, and the shown one starts to
    if (root._current && root._waiting) {
      root._current.destroy();
    } else {
      if (root._leaving) {
        fadeOut.stop();
        root._leaving.destroy();
      }
      fadeIn.stop();
      root._leaving = root._current;
    }
    root._current = next;
    root._waiting = true;
    if ("ready" in next && !next.ready)
      next.readyChanged.connect(() => {
        if (next === root._current && next.ready)
          root._reveal();
      });
    else
      root._reveal();
  }

  function _reveal() {
    const shown = root._current;
    root._waiting = false;
    if (!root._leaving || !Appearance.animations) {
      fadeIn.stop();
      shown.opacity = 1;
      if (root._leaving) {
        root._leaving.destroy();
        root._leaving = null;
      }
      return;
    }
    fadeIn.target = shown;
    fadeIn.restart();
    fadeOut.target = root._leaving;
    fadeOut.restart();
  }

  NumberAnimation {
    id: fadeIn
    property: "opacity"
    to: 1
    duration: Appearance.animNormal
    easing.type: Appearance.easing
  }

  NumberAnimation {
    id: fadeOut
    property: "opacity"
    to: 0
    duration: Appearance.animNormal
    easing.type: Appearance.easing
    onFinished: {
      if (root._leaving) {
        root._leaving.destroy();
        root._leaving = null;
      }
    }
  }
}
