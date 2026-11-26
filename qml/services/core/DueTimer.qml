pragma ComponentBehavior: Bound
import QtQuick

// One timer armed at an owner's `next` (ms on Date.now()'s clock, not above 0 = never);
// it re-reads the clock at least every `recheck` ms, so a `next` passed during
// a suspend fires within a minute of waking. `due` fires once per `next`
// value; the owner moves `next` on.
// Each owner builds its own.
QtObject {
  id: root

  // The deadline, in ms on `clock`'s clock; anything not above 0 (NaN too) = never
  property real next: 0
  // The clock read, in ms; tests replace it
  property var clock: () => Date.now()
  // The longest the inner timer is armed for, in ms
  readonly property int recheck: 60000
  // What the inner timer is armed for, in ms; 0 = not armed
  readonly property int armedFor: root._armedFor

  // `next` has been reached (once per `next` value); `now` is the clock then
  signal due(real now)

  // Re-reads the clock: emits `due` or arms again
  function check() {
    root._arm(false);
  }

  onNextChanged: {
    root._fired = false;
    root._arm(true);
  }

  property int _armedFor: 0
  // `due` was emitted for the current `next`
  property bool _fired: false

  // fromChange: reached from a `next` change, so a past `next` is judged on
  // the next turn and an owner's own assignment never re-enters its handler
  function _arm(fromChange) {
    const now = root.clock();
    root._dueTimeout.stop();
    root._armedFor = 0;
    if (!(root.next > 0))
      return;
    if (root.next <= now) {
      if (fromChange) {
        root._dueTimeout.interval = 0;
        root._dueTimeout.start();
      } else if (!root._fired) {
        root._fired = true;
        root.due(now);
      }
      return;
    }
    const ms = Math.ceil(Math.min(root.next - now, root.recheck));
    root._dueTimeout.interval = ms;
    root._armedFor = ms;
    root._dueTimeout.start();
  }

  property Timer _dueTimeout: Timer {
    repeat: false
    onTriggered: root.check()
  }
}
