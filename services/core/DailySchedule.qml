pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.components.methods

// A daily window, `startAt` until `endAt` ("HH:MM"; past midnight when the
// end is earlier), that says when its state is due: `due(inWindow)` fires
// when the window opens or closes, when the schedule is turned on, and when
// new times move now across it. Nothing in between, so a change made by
// hand lasts until the next edge. What it last reported survives QML
// reloads (keyed by `name`), so a reload doesn't undo a change by hand; a
// restart reports afresh. Checked every 30 s, which also catches up after a
// suspend (a single timer to the next edge would stop with the clock).
QtObject {
  id: root

  // Unique per schedule: keeps its state across reloads
  required property string name
  // The user's switch: turned off, the schedule forgets its state, so
  // turning it on reports afresh
  property bool enabled: false
  // What the owner needs first (a tool found, a probe done): until then it
  // waits, keeping its state, since after a reload it comes back a moment
  // later and must not look newly turned on
  property bool ready: true
  property string startAt: ""
  property string endAt: ""

  signal due(bool inWindow)

  function check() {
    if (!root.enabled) {
      persisted.last = "";
      return;
    }
    if (!root.ready)
      return;
    const inWindow = Schedules.inWindow(Schedules.minutesOf(new Date()), root.startAt, root.endAt);
    const state = inWindow ? "in" : "out";
    if (persisted.last === state)
      return;
    persisted.last = state;
    console.log("[DailySchedule]", root.name, root.startAt, "-", root.endAt + ":", inWindow ? "in the window" : "outside it");
    root.due(inWindow);
  }

  onEnabledChanged: if (root._started)
    Qt.callLater(root.check)
  onReadyChanged: if (root._started)
    Qt.callLater(root.check)
  onStartAtChanged: if (root._started)
    Qt.callLater(root.check)
  onEndAtChanged: if (root._started)
    Qt.callLater(root.check)

  property bool _started: false

  property PersistentProperties _state: PersistentProperties {
    id: persisted
    reloadableId: "axiomSchedule-" + root.name
    // "in" | "out" | "" (not reported since it was turned on)
    property string last: ""
  }

  property Timer _tick: Timer {
    interval: 30000
    repeat: true
    running: root.enabled
    onTriggered: root.check()
  }

  // The first check waits a moment: for the persisted state after a
  // reload, and for what the owner applies it to (the theme list)
  property Timer _start: Timer {
    interval: 1000
    running: true
    onTriggered: {
      root._started = true;
      root.check();
    }
  }
}
