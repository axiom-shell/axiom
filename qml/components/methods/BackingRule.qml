pragma Singleton

import QtQuick

// When chrome is drawn by the backing window (pure): the rule behind
// BlurManager.backsOn, which answers it for a screen with its inputs (one
// decision, read from its output).
QtObject {
  // Whether one chrome surface leaves its fill to the backing window: backing
  // is on, and it is on the Overlay layer or no fullscreen window fades its
  // layer out. `o`: { backing, fullscreen, onOverlay }.
  function backsOn(o) {
    if (!o.backing)
      return false;
    return o.onOverlay || !o.fullscreen;
  }
}
