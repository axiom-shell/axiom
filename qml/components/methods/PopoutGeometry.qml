pragma Singleton
import QtQuick

// Which popouts give way to which (PopoutManager): every popout reports
// its footprint (rects in screen px, from SurfaceOutline.footprint, fillets
// included), and one opening closes only what it actually covers, by rank.
// No files, services or config.
//
// An entry is { id, kind, pinned, resident, screen, parentId, phase,
// footprint }:
// - kind: "toast" | "dock" | "osd" | "bar" | "menu" | "launcher" |
//   "submenu"
// - pinned: held open by the user; ranks lowest whatever its kind
// - resident: gives way and comes back (the dock, pinned popouts, a menu
//   previewing from its editor) rather than closing for good
// - phase: "open" | "yielded", as PopoutManager registers them; "opening"
//   (one `resumable` brings back) collides as "open" does
QtObject {
  id: root

  // Lowest first. A submenu takes its parent's rank; notification toasts
  // rank under them all (-1), giving way to anything that covers them
  // but a dock (rankAgainst)
  readonly property var ranks: ["pinned", "dock", "osd", "bar", "menu", "launcher"]

  // An entry's rank, `parent` its parent's entry for a submenu
  function rankOf(entry, parent) {
    if (entry.kind === "toast")
      return -1;
    if (entry.kind === "submenu")
      return parent ? rankOf(parent, null) : 0;
    if (entry.pinned)
      return 0;
    return Math.max(0, ranks.indexOf(entry.kind));
  }

  // An entry's rank against another: its own (`rankOf`), but a notification
  // toast ranks one over a dock, whatever their ranks, so a dock gives way
  // to a stack over it (seeing the notification comes first)
  function rankAgainst(entry, parent, other) {
    if (entry.kind === "toast" && other.kind === "dock")
      return rankOf(other, null) + 1;
    return rankOf(entry, parent);
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
  // - entries on other screens, yielded ones, the claim itself,
  //   and its own parent or submenu never collide with it
  // - one ranked above it that it overlaps refuses it (`blockedBy`)
  // - else every one ranked at or below it that it overlaps goes: a
  //   resident yields, any other is evicted
  // - `claim.resuming` (a resident coming back once something closed):
  //   one of the same rank also refuses it, so two residents never take
  //   turns evicting each other
  // - a toast and a dock: the dock goes (`rankAgainst`), and a yielded
  //   stack still refuses a dock coming back
  function resolve(entries, claim) {
    const byId = {};
    for (const e of entries)
      byId[e.id] = e;
    const evict = [];
    const yields = [];
    for (const e of entries) {
      if (e.id === claim.id || e.screen !== claim.screen)
        continue;
      // A stack waiting under a popout still keeps a dock it put away from
      // coming back (only `resuming`: a dock showing, or revealed, while a
      // stack waits hidden isn't put away by it, so a dock's own footprint
      // changing as it magnifies never hides it under the pointer while the
      // stack waits hidden; grown into a shown stack it gives way, as into
      // a popout today)
      if (e.phase === "yielded" && !(claim.resuming && e.kind === "toast" && claim.kind === "dock"))
        continue;
      if (e.parentId === claim.id || claim.parentId === e.id)
        continue;
      if (!intersects(e.footprint, claim.footprint))
        continue;
      const rank = rankAgainst(claim, byId[claim.parentId], e);
      const other = rankAgainst(e, byId[e.parentId], claim);
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
    // Yielded stacks stay: they still keep a dock from coming back
    let showing = entries.filter(e => e.phase !== "yielded" || e.kind === "toast");
    const back = [];
    for (const e of yielded) {
      const claim = Object.assign({}, e, {
        "resuming": true
      });
      const r = resolve(showing, claim);
      if (r.allowed) {
        back.push(e.id);
        showing = showing.filter(s => s.id !== e.id).concat([Object.assign({}, e, {
            "phase": "opening"
          })]);
      }
    }
    return back;
  }
}
