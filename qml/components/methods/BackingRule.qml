pragma Singleton

import QtQuick

// When chrome is drawn by the backing window (pure): the rule behind
// BlurManager.backsOn, which answers it for a screen with its inputs (one
// decision, read from its output).
QtObject {
  // Whether one chrome surface leaves its fill to the backing window: backing
  // is on, and no fullscreen window fades its layer out, or the surface is
  // on the Overlay layer and the backing window is too (a surface over a
  // fullscreen window fills itself where the backing window stays under it).
  // `o`: { backing, fullscreen, onOverlay, backingOnOverlay }.
  function backsOn(o) {
    if (!o.backing)
      return false;
    return !o.fullscreen || (o.onOverlay && o.backingOnOverlay);
  }
}
