pragma Singleton
import QtQuick

// Pure helpers for the dock: which apps it shows (pinned ones, then running
// ones), which window a click goes to, how big each icon is under the
// pointer, and whether a window covers it. Windows are the compositor's
// (docs/dev/compositor/contract.md: id, appId, workspaceId, output,
// focusRank, x, y, w, h, hidden). No file access, processes or services.
QtObject {
  id: root

  // Whether a window counts on a dock: not hidden, and in its scope
  // ("all" | "monitor" | "workspace"; `output` is the screen's name)
  function inScope(win, scope, output, workspaceId) {
    if (!win || win.hidden)
      return false;
    if (scope === "monitor")
      return win.output === output;
    if (scope === "workspace")
      return win.workspaceId === workspaceId;
    return true;
  }

  // The dock's items: [{ key, pinned, windows }], the pinned apps first in
  // their order, then (with showRunning) the apps of the other windows in
  // the order their first window appears. `resolve(win)` gives a window's
  // app key (its desktop entry id, else its class). Each item's windows
  // are most recently focused first.
  function buildItems(pinned, windows, resolve, showRunning) {
    const byKey = {};
    const order = [];
    for (const win of windows) {
      const key = resolve(win);
      if (!key)
        continue;
      if (!byKey[key]) {
        byKey[key] = [];
        order.push(key);
      }
      byKey[key].push(win);
    }
    const recent = list => list.slice().sort((a, b) => (a.focusRank ?? 0) - (b.focusRank ?? 0));
    const items = pinned.filter((key, i) => key && pinned.indexOf(key) === i).map(key => ({
          "key": key,
          "pinned": true,
          "windows": recent(byKey[key] ?? [])
        }));
    if (showRunning) {
      for (const key of order) {
        if (!pinned.includes(key))
          items.push({
            "key": key,
            "pinned": false,
            "windows": recent(byKey[key])
          });
      }
    }
    return items;
  }

  // The window a click on an app focuses: its most recent one, or, when
  // one of its windows is already focused, the next in a stable order (so
  // repeated clicks cycle through them). Empty when it has none.
  function clickTarget(windows, focusedId) {
    if (windows.length === 0)
      return "";
    const stable = windows.map(w => w.id).sort();
    const at = stable.indexOf(focusedId);
    if (at < 0)
      return windows[0].id;
    return stable[(at + 1) % stable.length];
  }

  // Each icon's size along the dock with the pointer at `pos` (pixels from
  // the start of the row as laid out at rest, null when it's elsewhere;
  // negative before the row's first icon, as the grown box reaches past
  // it): the icon under it `max`, falling off as a cosine to `base` at
  // `range` icons away. Distances are taken at rest, so the icon under the
  // pointer stays under it while the row grows.
  function magnifiedSizes(count, pos, base, max, range, spacing) {
    const sizes = [];
    const step = base + spacing;
    for (let i = 0; i < count; i++) {
      if (pos === null || range <= 0 || max <= base) {
        sizes.push(base);
        continue;
      }
      const distance = Math.abs(pos - (i * step + base / 2)) / step;
      sizes.push(distance >= range ? base : base + (max - base) * (Math.cos(Math.PI * distance / range) + 1) / 2);
    }
    return sizes;
  }

  // Whether two rects ({ x, y, width, height }) overlap
  function overlaps(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
  }

  // Whether any of the windows (in the same global coordinates as `rect`)
  // covers the rect: by its `cover` where it has one (a place the
  // compositor doesn't give exactly), else its geometry
  function covered(rect, windows) {
    return windows.some(win => {
      const w = win.cover ?? win;
      return w.w > 0 && w.h > 0 && root.overlaps(rect, {
        "x": w.x,
        "y": w.y,
        "width": w.w,
        "height": w.h
      });
    });
  }
}
