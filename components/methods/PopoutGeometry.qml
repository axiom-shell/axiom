pragma Singleton
import QtQuick

// Which popouts give way to which (PopoutManager): every popout reports
// its footprint (rects in screen px, from SurfaceOutline.footprint, fillets
// included), and one opening closes only what it actually covers, by rank.
// No files, services or config.
//
// An entry is { id, kind, pinned, resident, screen, parentId, phase,
// footprint }:
// - kind: "dock" | "osd" | "bar" | "menu" | "launcher" | "submenu"
// - pinned: held open by the user; ranks lowest whatever its kind
// - resident: gives way and comes back (the dock, pinned popouts, a menu
//   previewing from its editor) rather than closing for good
// - phase: "open" | "yielded", as PopoutManager registers them; "opening"
//   (one `resumable` brings back) collides as "open" does, "closing" as
//   "yielded" doesn't
QtObject {
  id: root

  // Lowest first. A submenu takes its parent's rank.
  readonly property var ranks: ["pinned", "dock", "osd", "bar", "menu", "launcher"]

  // An entry's rank, `parent` its parent's entry for a submenu
  function rankOf(entry, parent) {
    if (entry.kind === "submenu")
      return parent ? rankOf(parent, null) : 0;
    if (entry.pinned)
      return 0;
    return Math.max(0, ranks.indexOf(entry.kind));
  }

  // Whether two rects ({ x, y, width, height }) overlap by more than half a
  // pixel each way (an edge shared by surfaces meeting isn't an overlap)
  function rectsOverlap(a, b) {
    const w = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
    const h = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
    return w > 0.5 && h > 0.5;
  }

  // Whether two footprints (arrays of rects) overlap anywhere
  function intersects(a, b) {
    return (a ?? []).some(r => (b ?? []).some(q => rectsOverlap(r, q)));
  }

  // A rect moved by an origin ({ x, y }): a footprint in a window's
  // coordinates onto the screen
  function offset(rects, origin) {
    return (rects ?? []).map(r => ({
          "x": r.x + origin.x,
          "y": r.y + origin.y,
          "width": r.width,
          "height": r.height
        }));
  }

  // What happens when `claim` (an entry) asks to show among `entries`:
  // { allowed, evict: [ids], yield: [ids], blockedBy: id | "" }
  // - entries on other screens, closing or yielded ones, the claim itself,
  //   and its own parent or submenu never collide with it
  // - one ranked above it that it overlaps refuses it (`blockedBy`)
  // - else every one ranked at or below it that it overlaps goes: a
  //   resident yields, any other is evicted
  // - `claim.resuming` (a resident coming back once something closed):
  //   one of the same rank also refuses it, so two residents never take
  //   turns evicting each other
  function resolve(entries, claim) {
    const byId = {};
    for (const e of entries)
      byId[e.id] = e;
    const rank = rankOf(claim, byId[claim.parentId]);
    const evict = [];
    const yields = [];
    for (const e of entries) {
      if (e.id === claim.id || e.screen !== claim.screen)
        continue;
      if (e.phase === "closing" || e.phase === "yielded")
        continue;
      if (e.parentId === claim.id || claim.parentId === e.id)
        continue;
      // A submenu goes with its parent: only the parent collides
      if (e.kind === "submenu" && claim.parentId && e.parentId === claim.parentId)
        continue;
      if (!intersects(e.footprint, claim.footprint))
        continue;
      const other = rankOf(e, byId[e.parentId]);
      if (other > rank || (claim.resuming && other === rank))
        return {
          "allowed": false,
          "evict": [],
          "yield": [],
          "blockedBy": e.id
        };
      if (e.kind === "submenu")
        (byId[e.parentId]?.resident ? yields : evict).push(e.parentId);
      else
        (e.resident ? yields : evict).push(e.id);
    }
    const unique = list => list.filter((id, i) => id && list.indexOf(id) === i);
    return {
      "allowed": true,
      "evict": unique(evict),
      "yield": unique(yields),
      "blockedBy": ""
    };
  }

  // Yielded residents that may come back now (highest rank first, each
  // checked against what's showing and those already coming back)
  function resumable(entries) {
    const yielded = entries.filter(e => e.phase === "yielded").sort((a, b) => rankOf(b, null) - rankOf(a, null));
    let showing = entries.filter(e => e.phase !== "yielded" && e.phase !== "closing");
    const back = [];
    for (const e of yielded) {
      const claim = Object.assign({}, e, {
        "resuming": true
      });
      const r = resolve(showing, claim);
      if (r.allowed) {
        back.push(e.id);
        showing = showing.concat([Object.assign({}, e, {
            "phase": "opening"
          })]);
      }
    }
    return back;
  }

  // How far a stack of toasts at `rect` (screen px, at rest) on `screen`
  // moves along `axis` ("x" | "y") by `sign` (1 | -1) to clear the
  // popouts showing there (`entries`, closing and yielded ones aside),
  // `gap` px past the furthest; capped at `room`. Toasts hold no claim:
  // they read the popouts' footprints and make way, never the other way.
  function makeWay(entries, screen, rect, axis, sign, gap, room) {
    const others = [].concat(...entries.filter(e => e.screen === screen && e.phase !== "closing" && e.phase !== "yielded").map(e => e.footprint ?? []));
    const pos = axis === "x" ? "x" : "y";
    const size = axis === "x" ? "width" : "height";
    let shift = 0;
    // Each pass clears what the last shift ran into
    for (let pass = 0; pass < 8; pass++) {
      const moved = Object.assign({}, rect);
      moved[pos] = rect[pos] + shift * sign;
      const hit = others.filter(r => rectsOverlap(r, moved));
      if (hit.length === 0)
        break;
      for (const r of hit) {
        const need = sign > 0 ? r[pos] + r[size] - rect[pos] + gap : rect[pos] + rect[size] - r[pos] + gap;
        shift = Math.max(shift, need);
      }
      if (shift >= room)
        return room;
    }
    return Math.min(shift, room);
  }
}
