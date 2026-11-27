pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// What each owner holds (a request, a frame, a window), one entry per owner,
// for the service that owns it. Not a singleton: each service holds its own.
QtObject {
  id: root

  // [{ owner, value }], a new owner appends, a re-set keeps its place
  readonly property var entries: root._entries
  readonly property var values: root.entries.map(e => e.value)
  readonly property bool active: root.entries.length > 0

  // Holds `value` (`true` when omitted) for `owner`. Setting an equal value is
  // a no-op, so an owner that sets often can't churn every binding derived
  // from the entries (see the 25 GB note in CLAUDE.md › UI).
  function set(owner, value) {
    const held = value === undefined ? true : value;
    const index = root._entries.findIndex(e => e.owner === owner);
    if (index >= 0 && Utils.deepEqual(root._entries[index].value, held))
      return;
    const entry = {
      "owner": owner,
      "value": held
    };
    if (index < 0)
      root._entries = root._entries.concat([entry]);
    else
      root._entries = root._entries.map((e, i) => i === index ? entry : e);
  }

  // Forgets `owner`; an owner not held changes nothing
  function drop(owner) {
    if (root._entries.some(e => e.owner === owner))
      root._entries = root._entries.filter(e => e.owner !== owner);
  }

  // What `owner` holds, `undefined` when it holds nothing
  function valueOf(owner) {
    return root._entries.find(e => e.owner === owner)?.value;
  }

  property var _entries: []
}
