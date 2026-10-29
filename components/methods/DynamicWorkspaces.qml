pragma Singleton
import QtQuick

// niri's workspaces for a compositor that only has ids (Hyprland, under the
// scrolling layout): each output's workspaces are its block's ids from the
// first, without gaps, with one empty one after the last (and any it
// borrows from another output's block before that one). `workspaces`
// shows them so; `compaction` plans the window moves that close a gap once
// a workspace in the middle is left empty.
QtObject {
  id: root

  // The workspaces as niri would have them: each output's (by `bases`: {
  // [name]: first id }, `size` ids each) in id order, then the ones it
  // borrows (numbered ones outside its block, such as an unplugged
  // monitor's, which Hyprland hands back on replug), then an empty one
  // after the last unless that one is already empty. Special and named
  // workspaces (ids below 1) are left out. real: [{ id, name, output,
  // windowCount, active, focused }]. Returns the same shape.
  function workspaces(real, bases, size) {
    const result = [];
    for (const output of Object.keys(bases)) {
      const base = bases[output];
      const mine = (real ?? []).filter(ws => ws.output === output && ws.id >= 1).sort((a, b) => a.id - b.id);
      const own = mine.filter(ws => ws.id >= base && ws.id < base + size);
      const borrowed = mine.filter(ws => ws.id < base || ws.id >= base + size);
      const listed = own.concat(borrowed);
      const last = own[own.length - 1];
      const next = last ? last.id + 1 : base;
      const lastEmpty = listed.length > 0 && listed[listed.length - 1].windowCount === 0;
      result.push(...listed);
      if (!lastEmpty && next < base + size)
        result.push({
          "id": next,
          "name": String(next),
          "output": output,
          "windowCount": 0,
          "active": false,
          "focused": false
        });
    }
    return result;
  }

  // The moves that close the gaps in each output's block: its workspaces
  // with windows and its active one, in id order, go to its first ids
  // (borrowed ones, outside its block, stay where they are). The
  // active one stays where it is in that order even when empty (niri drops
  // an empty workspace only once it's left). Only ever moves windows to a
  // lower id, so working through `moves` in order never merges two.
  // monitors: [{ name, active, focused }]; windows: [{ id, workspace }];
  // bases, size as workspaces(). Returns { moves: [{ id, to }], focus:
  // [{ monitor, id, stay }] (each output whose active workspace moved, then
  // the focused one, last, with `stay` when only the monitor needs focus
  // back: focusing the workspace it's on can go back to the one before,
  // with Hyprland's workspace_back_and_forth), changed }.
  function compaction(monitors, windows, bases, size) {
    const moves = [];
    const focus = [];
    let focused = null;
    for (const monitor of monitors ?? []) {
      const base = bases[monitor.name];
      if (base === undefined)
        continue;
      const inBlock = id => id >= base && id < base + size;
      const ids = (windows ?? []).map(w => w.workspace).filter(inBlock);
      if (inBlock(monitor.active))
        ids.push(monitor.active);
      const order = ids.filter((id, i) => ids.indexOf(id) === i).sort((a, b) => a - b);
      const to = order.reduce((map, id, i) => {
        map[id] = base + i;
        return map;
      }, {});
      for (const w of windows ?? []) {
        if (to[w.workspace] !== undefined && to[w.workspace] !== w.workspace)
          moves.push({
            "id": w.id,
            "from": w.workspace,
            "to": to[w.workspace]
          });
      }
      const active = to[monitor.active] ?? monitor.active;
      if (monitor.focused)
        focused = {
          "monitor": monitor.name,
          "id": active,
          "stay": active === monitor.active
        };
      else if (active !== monitor.active)
        focus.push({
          "monitor": monitor.name,
          "id": active,
          "stay": false
        });
    }
    // Lowest first, so a window never lands on a workspace still to be
    // emptied
    moves.sort((a, b) => a.to - b.to || a.from - b.from);
    const changed = moves.length > 0 || focus.length > 0 || (focused !== null && !focused.stay);
    // The focused output gets focus back after the others took it
    if (focused && (focus.length > 0 || !focused.stay))
      focus.push(focused);
    return {
      "moves": moves.map(m => ({
            "id": m.id,
            "to": m.to
          })),
      "focus": focus,
      "changed": changed
    };
  }
}
