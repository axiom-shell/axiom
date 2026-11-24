pragma ComponentBehavior: Bound
import QtQuick

// One timer armed at an owner's `next` (ms on Date.now()'s clock, 0 = never);
// it re-reads the clock at least every `recheck` ms, so a `next` passed during
// a suspend fires within a minute of waking. `due` fires once per `next`
// value; the owner moves `next` on.
// Each owner builds its own.
QtObject {
  id: root

  // The deadline, in ms on `clock`'s clock; 0 or less = never
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
    root._dueFor = 0;
    root._arm(true);
  }

  property int _armedFor: 0
  // The `next` value `due` was emitted for, 0 for none
  property real _dueFor: 0

  // fromChange: reached from a `next` change, so a past `next` is judged on
  // the next turn and an owner's own assignment never re-enters its handler
  function _arm(fromChange) {
    const now = root.clock();
    root._dueTimeout.stop();
    root._armedFor = 0;
    if (root.next <= 0)
      return;
    if (root.next <= now) {
      if (fromChange) {
        Qt.callLater(root.check);
      } else if (root._dueFor !== root.next) {
        root._dueFor = root.next;
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
