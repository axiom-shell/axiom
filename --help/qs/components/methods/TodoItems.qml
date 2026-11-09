pragma Singleton
import QtQuick

// The todo list's items and every change to them, for TodoManager: each
// returns a new list and leaves its input alone. An item is { uid, summary,
// done, created, completed (epoch ms, 0 while open), due (epoch ms, 0 for
// none), order }, the fields a CalDAV VTODO has (UID, SUMMARY, STATUS,
// CREATED, COMPLETED, DUE), so a sync can map them one to one.
QtObject {
  id: root

  // `list` (from a file: anything) as valid items, in order, numbered
  // 0, 1, …; entries without a uid or summary are dropped, a repeated uid
  // keeps its first
  function normalize(list) {
    const seen = {};
    const items = (Array.isArray(list) ? list : []).filter(item => {
      const ok = item && typeof item === "object" && typeof item.uid === "string" && item.uid !== "" && typeof item.summary === "string" && item.summary.trim() !== "" && !seen[item.uid];
      if (ok)
        seen[item.uid] = true;
      return ok;
    }).map((item, index) => ({
          "uid": item.uid,
          "summary": item.summary.trim(),
          "done": item.done === true,
          "created": root._number(item.created),
          "completed": item.done === true ? root._number(item.completed) : 0,
          "due": root._number(item.due),
          "order": typeof item.order === "number" && isFinite(item.order) ? item.order : index
        }));
    return root._renumber(items.sort((a, b) => a.order - b.order));
  }

  // A new open item at the end, or `list` unchanged for an empty summary
  function add(list, summary, now, uid) {
    const text = String(summary ?? "").trim();
    if (text === "" || !uid)
      return list;
    return root._renumber(list.concat([
      {
        "uid": uid,
        "summary": text,
        "done": false,
        "created": now,
        "completed": 0,
        "due": 0,
        "order": list.length
      }
    ]));
  }

  // Done ↔ open; `done` given sets it instead. `list` itself when nothing
  // changes (an unknown uid, already in that state)
  function toggle(list, uid, now, done) {
    const item = root.find(list, uid);
    const next = item ? (done === undefined ? !item.done : done === true) : false;
    if (!item || next === item.done)
      return list;
    return list.map(entry => entry.uid !== uid ? entry : Object.assign({}, entry, {
        "done": next,
        "completed": next ? now : 0
      }));
  }

  // A new summary; an empty one, the same one or an unknown uid leaves
  // `list` itself
  function rename(list, uid, summary) {
    const text = String(summary ?? "").trim();
    const item = root.find(list, uid);
    if (text === "" || !item || item.summary === text)
      return list;
    return list.map(entry => entry.uid === uid ? Object.assign({}, entry, {
        "summary": text
      }) : entry);
  }

  function remove(list, uid) {
    return root.find(list, uid) ? root._renumber(list.filter(item => item.uid !== uid)) : list;
  }

  // Moves an item to `index` in the whole list (clamped)
  function move(list, uid, index) {
    const from = list.findIndex(item => item.uid === uid);
    if (from < 0)
      return list;
    const items = list.slice();
    const moved = items.splice(from, 1)[0];
    items.splice(Math.max(0, Math.min(items.length, index)), 0, moved);
    return root._renumber(items);
  }

  function clearCompleted(list) {
    return list.some(item => item.done) ? root._renumber(list.filter(item => !item.done)) : list;
  }

  // What a list shows: the open items in order, then (with `showCompleted`)
  // the done ones, the last finished first
  function shown(list, showCompleted) {
    const open = list.filter(item => !item.done);
    if (!showCompleted)
      return open;
    return open.concat(list.filter(item => item.done).sort((a, b) => b.completed - a.completed));
  }

  function openCount(list) {
    return list.filter(item => !item.done).length;
  }

  function find(list, uid) {
    return list.find(item => item.uid === uid) ?? null;
  }

  function _number(value) {
    return typeof value === "number" && isFinite(value) && value > 0 ? value : 0;
  }

  function _renumber(items) {
    return items.map((item, index) => item.order === index ? item : Object.assign({}, item, {
        "order": index
      }));
  }
}
