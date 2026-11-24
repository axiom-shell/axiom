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

  function init() {
    root.now = 0;
  }

  function test_neverWhenZero() {
    const t = make({});
    compare(t.armedFor, 0);
    wait(0);
    compare(root.fired.length, 0);
  }

  function test_armsForTheWait() {
    const t = make({});
    t.next = root.now + 5000;
    compare(t.armedFor, 5000);
  }

  function test_armsNoLongerThanRecheck() {
    const t = make({});
    t.next = root.now + 3600000;
    compare(t.armedFor, 60000);
  }

  function test_suspendFiresOnCheck() {
    const t = make({});
    t.next = 3600000;
    compare(t.armedFor, 60000);
    root.now = 3700000;
    t.check();
    compare(root.fired.length, 1);
    compare(root.fired[0], 3700000);
    compare(t.armedFor, 0);
  }

  function test_passedNextFiresOnTheNextTurn() {
    root.now = 1000;
    const t = make({});
    t.next = 500;
    compare(root.fired.length, 0, "not synchronously");
    wait(0);
    compare(root.fired.length, 1);
    compare(root.fired[0], 1000);
  }

  function test_oneDuePerNext() {
    const t = make({});
    t.next = 1000;
    root.now = 2000;
    t.check();
    t.check();
    compare(root.fired.length, 1);
  }

  function test_nextMovedOnArmsAgain() {
    const t = make({});
    t.next = 1000;
    root.now = 2000;
    t.check();
    compare(root.fired.length, 1);
    t.next = 7000;
    compare(t.armedFor, 5000);
  }

  function test_negativeNextNever() {
    const t = make({});
    t.next = -5;
    compare(t.armedFor, 0);
    t.check();
    wait(0);
    compare(root.fired.length, 0);
  }
}
