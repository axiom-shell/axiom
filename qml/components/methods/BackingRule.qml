pragma Singleton

import QtQuick

// When chrome is drawn by the backing window (pure): the rule behind
// BlurManager.backingOn and BlurManager.backsOn, which answer it for a
// screen with their inputs (one decision, read from its output).
QtObject {
  // Whether surfaces leave their fill to the backing window: drawn wherever
  // the chrome is see-through (the compositor blurs it only where blur is
  // active), not on a screen that fills solid, and once its windows are
  // built. `o`: { translucent, opaque, ready }.
  function backingOn(o) {
    return o.translucent && !o.opaque && o.ready;
  }

  // Whether one chrome surface leaves its fill to the backing window: backing
  // is on, and it is on the Overlay layer or no fullscreen window fades its
  // layer out. `o`: { backing, fullscreen, onOverlay }.
  function backsOn(o) {
    if (!o.backing)
      return false;
    return o.onOverlay || !o.fullscreen;
  }
}
