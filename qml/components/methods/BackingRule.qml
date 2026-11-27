pragma Singleton

import QtQuick

// When chrome is drawn by the backing window (pure): the rule behind
// BlurManager.backingOn and BlurManager.backsOn, which answer it for a
// screen with their inputs (one decision, read from its output).
QtObject {
  // Whether surfaces leave their fill to the backing window: in every mode
  // (opaque, see-through, blurred or not), once its windows are built.
  // `o`: { translucent, opaque, ready }; translucent and opaque were read by
  // the rule before opaque chrome was backed and are unread now, kept so that
  // rolling the mode back changes this body alone.
  function backingOn(o) {
    return o.ready;
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
