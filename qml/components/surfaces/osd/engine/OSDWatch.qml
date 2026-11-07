pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods
import qs.services.ui

// The base of an OSD system's watcher (systems/<Name>/<Name>Watch.qml,
// the only file of a system that reads services): it keeps `state`, a
// snapshot by exposed key, bound to its services, and the base judges each
// change of it through OSDEngine by its definition and reports what shows
// (`change`). Nothing counts for its first 1.5 s, while services settle
// (the LEDs' first reading, PipeWire binding, UPower and D-Bus answering):
// those only set the state the next change is judged from
// (docs/dev/features/osd.md › Engine). A QtObject (an Item's `state` is
// taken): what it declares inside (Connections, Timers) goes in `data`.
QtObject {
  id: root

  default property list<QtObject> data

  // Its definition (an OSDSystem), set by OSDSystemHost
  property var definition: null
  // Its item in the OSD's `systems` list (the definition's `options`)
  property var options: ({})
  // The screen its OSD is on (a ShellScreen; Brightness reads its
  // monitor) and the OSD's id (Message takes only its own OSD's)
  property var screen: null
  property string osdId: ""

  // The services it holds while it exists (acquire(owner) /
  // release(owner)): polled ones it reads
  property var holds: []

  // Its state now, by exposed key: { value, … } (scalar), { members, … }
  // (set), { event, seq } (event; pulse() sets one), a bar's { level,
  // muted }; `available: false` for none to judge
  property var state: ({})

  // Whether a change of `key` from `before` to `after` may be the user's:
  // false while its service is still settling (an audio device switching
  // or binding), which only moves the state on. Ignored for a system that
  // counts `anyone`'s changes
  function settled(key, before, after) {
    return true;
  }

  // A click on its card (a change the definition's activate() hands back
  // with ""): acts on what it says (a drive's opens it)
  function activate(change) {
  }

  // Its OSD opened (on this screen): picks up what changed outside axiom
  // that nothing pushes (Brightness rereads the monitors its bar shows)
  function opened() {
  }

  // A bar without a design of its own (OSDLevelBar's StyledVolumeBar)
  // dragged or scrolled to `level` (0-1), or its icon clicked (shown
  // clickable while its state has `muted`): sets it in its service
  function setLevel(key, level) {
  }
  function iconClicked(key) {
  }

  // What shows for a change: OSDEngine.judge's, with { system }
  signal change(var what)

  // Its tiles now, by tile key (OSDEngine.tileOf)
  readonly property var tiles: {
    const out = {};
    for (const e of root.definition?.exposes ?? [])
      if (OSDEngine.partOf(root.definition, e.key) === "tile")
        out[e.key] = OSDEngine.tileOf(root.definition, e.key, root.state?.[e.key]);
    return out;
  }

  // Sets `key`'s event (the event model) in `events`, which `state` reads
  // (`"drive": watch.events.drive ?? { event: null }`): each one new, even
  // one like the last
  function pulse(key, event) {
    const next = Object.assign({}, root.events);
    next[key] = {
      "event": event,
      "seq": (root.events[key]?.seq ?? 0) + 1
    };
    root.events = next;
  }
  property var events: ({})

  // The state last judged, by key (OSDEngine.remember's: a gap's value
  // kept)
  property var _last: ({})
  property bool _armed: false

  // One service change sets several keys at once: judged once it's all in
  function _check() {
    const def = root.definition;
    if (!def)
      return;
    const at = Date.now();
    const before = root._last;
    const after = Object.assign({}, root.state ?? {});
    const changes = [];
    for (const e of def.exposes ?? []) {
      const was = before[e.key];
      const now = after[e.key];
      if (OSDEngine.same(OSDEngine.policy(def, e.key, "model"), was, now))
        continue;
      const mark = OSDEngine.markOf(def, e.key);
      const what = OSDEngine.judge(def, e.key, was, now, {
        "at": at,
        "byUser": ShellManager.fromScreen(mark, OSDEngine.policy(def, e.key, "userWindow")),
        "settled": root.settled(e.key, was, now),
        "before": before,
        "after": after
      });
      if (what)
        changes.push(Object.assign({
          "system": def.type
        }, what));
    }
    // A keepThroughGap value keeps what it had through an empty reading
    root._last = OSDEngine.remember(def, before, after);
    if (root._armed)
      changes.forEach(what => root.change(what));
  }

  onStateChanged: Qt.callLater(root._check)
  onDefinitionChanged: Qt.callLater(root._check)

  readonly property Timer _settle: Timer {
    // behaviour timing: how long services take to report their state
    interval: 1500
    running: true
    onTriggered: root._armed = true
  }

  Component.onCompleted: {
    for (const service of root.holds)
      service.acquire(root);
    root._check();
  }
  Component.onDestruction: {
    for (const service of root.holds)
      service.release(root);
  }
}
