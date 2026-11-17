pragma ComponentBehavior: Bound
import QtQuick

// The 400 ms after a modal prompt shows during which it takes no keys and
// answers no click, so typing meant for another window doesn't answer it
// (PromptCard, PolkitCard). `rearm()` starts it again.
Timer {
  id: root

  property bool settled: false

  function rearm() {
    root.settled = false;
    root.restart();
  }

  interval: 400
  onTriggered: root.settled = true
}
