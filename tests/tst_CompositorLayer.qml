import QtQuick
import QtTest
import qs.components.methods

TestCase {
  id: test
  name: "CompositorLayer"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  function test_hex() {
    compare(shared.calls.CompositorLayer.hex({
      "r": 1,
      "g": 0,
      "b": 0.5
    }), "ff0080");
  }
}
