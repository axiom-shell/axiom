import QtQuick
import QtTest

// DueTimer (services/core, loaded from its file: it imports only QtQuick):
// armed for `next` but never longer than a minute, so a `next` passed during
// a suspend fires on the next check; one `due` per `next` value.
TestCase {
  id: root

  name: "DueTimer"
  when: windowShown

  property real now: 0
  // The `now` of each `due` of the timer last made
  property var fired: []

  // `next` is assigned after make() returns: set in the props it would arm
  // through onNextChanged before `clock` is in place
  function make(props) {
    const component = Qt.createComponent(Qt.resolvedUrl("../qml/services/core/DueTimer.qml"));
    compare(component.status, Component.Ready, component.errorString());
    const timer = createTemporaryObject(component, root, Object.assign({
      "clock": () => root.now
    }, props));
    verify(timer);
    root.fired = [];
    timer.due.connect(n => root.fired.push(n));
    return timer;
  }

  // What the inner timer is armed for, in ms; 0 = not armed
  function armed(t) {
    return t._dueTimeout.running ? t._dueTimeout.interval : 0;
  }

  function init() {
    root.now = 0;
  }

  function test_never_when_zero() {
    const t = make({});
    t.next = root.now + 5000;
    compare(armed(t), 5000);
    t.next = 0;
    compare(armed(t), 0);
    verify(!t._dueTimeout.running);
    wait(0);
    compare(root.fired.length, 0);
  }

  function test_nan_is_never() {
    const t = make({});
    t.next = NaN;
    compare(armed(t), 0);
    verify(!t._dueTimeout.running);
    wait(50);
    compare(root.fired.length, 0);
  }

  function test_timer_fires_at_next() {
    const t = make({});
    t.next = root.now + 50;
    compare(armed(t), 50);
    root.now = 100;
    tryCompare(root.fired, "length", 1);
    compare(armed(t), 0);
  }

  function test_next_moved_earlier_while_armed() {
    const t = make({});
    t.next = root.now + 30000;
    compare(armed(t), 30000);
    t.next = root.now + 5000;
    compare(armed(t), 5000);
  }

  function test_same_past_next_again_fires_again() {
    const t = make({});
    root.now = 2000;
    t.next = 1000;
    wait(0);
    compare(root.fired.length, 1);
    t.next = 7000;
    t.next = 1000;
    wait(0);
    compare(root.fired.length, 2);
  }

  function test_changed_again_before_the_turn_is_not_stale() {
    root.now = 1000;
    const t = make({});
    t.next = 500;
    t.next = 0;
    wait(0);
    compare(root.fired.length, 0);
  }

  function test_arms_for_the_wait() {
    const t = make({});
    t.next = root.now + 5000;
    compare(armed(t), 5000);
  }

  function test_arms_no_longer_than_recheck() {
    const t = make({});
    t.next = root.now + 3600000;
    compare(armed(t), 60000);
  }

  function test_suspend_fires_on_check() {
    const t = make({});
    t.next = 3600000;
    compare(armed(t), 60000);
    root.now = 3700000;
    t.check();
    compare(root.fired.length, 1);
    compare(root.fired[0], 3700000);
    compare(armed(t), 0);
  }

  function test_passed_next_fires_on_the_next_turn() {
    root.now = 1000;
    const t = make({});
    t.next = 500;
    compare(root.fired.length, 0, "not synchronously");
    compare(armed(t), 0);
    wait(0);
    compare(root.fired.length, 1);
    compare(root.fired[0], 1000);
  }

  function test_one_due_per_next() {
    const t = make({});
    t.next = 1000;
    root.now = 2000;
    t.check();
    t.check();
    compare(root.fired.length, 1);
  }

  function test_next_moved_on_arms_again() {
    const t = make({});
    t.next = 1000;
    root.now = 2000;
    t.check();
    compare(root.fired.length, 1);
    t.next = 7000;
    compare(armed(t), 5000);
  }

  function test_negative_next_never() {
    const t = make({});
    t.next = -5;
    compare(armed(t), 0);
    t.check();
    wait(0);
    compare(root.fired.length, 0);
  }
}
