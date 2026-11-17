import QtQuick
import QtTest

// ConfirmGate (services/core, loaded from its file: it imports only QtQuick):
// the first press arms and refuses, the second passes. A timeout lapses it
// (`expired`); a timeout of 0 never does.
TestCase {
  id: root

  name: "ConfirmGate"
  when: windowShown

  function make(timeout) {
    const component = Qt.createComponent(Qt.resolvedUrl("../qml/services/core/ConfirmGate.qml"));
    compare(component.status, Component.Ready, component.errorString());
    const gate = createTemporaryObject(component, root, {
      "timeout": timeout
    });
    verify(gate);
    return gate;
  }

  function test_no_timeout_stays_armed() {
    const gate = make(0);
    verify(!gate.pass("a", true), "the first press arms");
    wait(50);
    compare(gate.armed, "a", "still armed");
    verify(gate.pass("a", true), "the second passes");
    compare(gate.armed, "");
  }

  function test_timeout_lapses() {
    const gate = make(20);
    let expired = 0;
    gate.expired.connect(() => expired++);
    verify(!gate.pass("a", true));
    tryCompare(gate, "armed", "", 1000);
    compare(expired, 1);
  }
}
