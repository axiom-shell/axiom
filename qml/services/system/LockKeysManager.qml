pragma Singleton
import QtQuick
import qs.services.core

// Whether Caps Lock, Num Lock and Scroll Lock are on: axiom's `lockKeys`
// topic, which reads the keyboards' LEDs (the same on every compositor).
// Polled only while someone holds it: a focused password field's
// CapsLockHint, a LockKeys bar widget. Consumers acquire(owner) and
// release(owner); with none, everything reads off and unavailable, so a
// state from the last consumer never shows stale.
QtObject {
  id: root

  // False where no keyboard has a Caps Lock LED (a VM, a remote
  // session): nothing should claim the key is off
  property bool available: false
  property bool capsLock: false
  property bool numLock: false
  property bool scrollLock: false

  function acquire(owner) {
    _registry.acquire(owner, {});
  }

  function release(owner) {
    _registry.release(owner);
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}

  readonly property bool _active: _registry.active

  on_ActiveChanged: {
    if (root._active) {
      BackendManager.acquire("lockKeys", {});
      return;
    }
    BackendManager.release("lockKeys");
    root.available = false;
    root.capsLock = false;
    root.numLock = false;
    root.scrollLock = false;
  }

  Component.onCompleted: BackendManager.listen("lockKeys.state", state => {
    if (!root._active)
      return;
    root.available = state.available === true;
    root.capsLock = state.caps === true;
    root.numLock = state.num === true;
    root.scrollLock = state.scroll === true;
  })
}
