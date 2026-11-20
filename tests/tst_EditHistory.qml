import QtQuick
import QtTest

// EditHistory (services/ui, loaded from its file as tst_ConfirmGate loads
// ConfirmGate): edits keyed by one setting's path join one undo step, a
// different path is another step, and undo puts back only the newest
TestCase {
  id: root

  name: "EditHistory"

  function test_path_keys_merge_per_setting() {
    const component = Qt.createComponent(Qt.resolvedUrl("../qml/services/ui/EditHistory.qml"));
    compare(component.status, Component.Ready, component.errorString());
    let state = 0;
    const history = createTemporaryObject(component, root, {
      "snapshot": () => state,
      "restore": snap => {
        state = snap;
      }
    });
    verify(history);
    history.record("w:popout.properties.showVpn");
    state = 1;
    history.record("w:popout.properties.showVpn");
    state = 2;
    compare(history._undo.length, 1, "the same setting twice is one step");
    history.record("w:popout.sizing.contentSize");
    state = 3;
    compare(history._undo.length, 2, "another setting is a second step");
    history.undo();
    compare(state, 2, "undo puts back only the second");
    compare(history._undo.length, 1);
  }
}
