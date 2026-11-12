pragma Singleton
import QtQuick

// The Workspaces bar widget's cells as numbers: where each sits along its
// row when they differ in length (WorkspaceCellRow, ActiveCellIndicator).
// No file access, processes or services.
QtObject {
  id: root

  // A row of cells `lengths` long at rest (one per cell), `spacing` apart,
  // with cell `active` (-1: none) longer by `extra` (wide active: one
  // normal cell's length): { starts, lengths, total }, each cell's start
  // and length along the row and the row's whole length
  function layout(lengths, spacing, active, extra) {
    const starts = [];
    const shown = [];
    let along = 0;
    for (let i = 0; i < lengths.length; i++) {
      const length = lengths[i] + (i === active ? extra : 0);
      starts.push(along);
      shown.push(length);
      along += length + spacing;
    }
    return {
      "starts": starts,
      "lengths": shown,
      "total": lengths.length > 0 ? along - spacing : 0
    };
  }

  // Cells `lengths` long for what they show, each with the room it keeps
  // clear of its caps as a segment of the bar's run (`rooms`, one {
  // lead, trail } each, BarCells.cellRoom; null: none): their lengths
  function roomed(lengths, rooms) {
    return lengths.map((length, i) => length + (rooms?.[i]?.lead ?? 0) + (rooms?.[i]?.trail ?? 0));
  }

  // Where cell `index` starts along a row of cells `lengths` long at rest,
  // `spacing` apart: where the active box sits on it, as only cells after
  // the active one move when it widens (an index below 0 starts at 0, one
  // past the end where a next cell would)
  function startOf(lengths, spacing, index) {
    let along = 0;
    for (let i = 0; i < Math.min(index, lengths.length); i++)
      along += lengths[i] + spacing;
    return along;
  }

  // An app icon's size in a cell `thickness` thick (one alone, or each of
  // a row's)
  // About 0.65 of the cell, in whole pixels leaving an even margin, so a
  // centred icon sits on a whole pixel (an odd margin rounded it to one
  // side)
  function iconSize(thickness) {
    const t = Math.round(thickness);
    return t - 2 * Math.round(t * 0.175);
  }

  // The tallest a cell's content shows across, on a bar `thickness` thick
  // with text `fontSize`: its label (a symbol's, the largest drawn,
  // WorkspaceCell), or with `appIcons` an app icon if that's taller. From
  // the bar's sizes, never measured: what a cell keeps clear of its caps
  // (BarCells.cellRoom)
  function contentSize(thickness, fontSize, appIcons) {
    const label = Math.round(fontSize * 1.2);
    return appIcons ? Math.max(label, root.iconSize(thickness)) : label;
  }

  // The gap between a row's app icons
  function iconGap(thickness) {
    return Math.round(thickness * 0.1);
  }

  // A cell's length along the bar for `count` app icons side by side (the
  // Row layout): room for them all with a lone icon's room around them, and
  // never under `rest`
  function rowLength(count, thickness, rest) {
    const icon = root.iconSize(thickness);
    const along = count * icon + Math.max(0, count - 1) * root.iconGap(thickness) + (thickness - icon);
    return Math.max(rest, Math.ceil(along));
  }

  // A split cell (a scratchpad with `scratchpadSplit`) along the bar is
  // [pad][label ink][pad] divider [pad][icons ink][pad]: the divider splits
  // it into two compartments, each content centred in its own, the same pad
  // on all four sides. `label` is the label's ink length, `count` the app
  // icons, `along` the divider's (dividerAlong). The functions below give
  // each part; WorkspaceCell and CellContents only read them.

  // The padding round each content of a split cell, its ends and either
  // side of the divider (the gap between several icons stays iconGap)
  function splitPad(thickness) {
    return Math.round(thickness * 0.25);
  }

  // How far the divider reaches across the bar in a cell `thickness` thick
  // (a chevron's is shorter than a line's for its slant): the strip's
  // divider (StripDivider) too
  function dividerLength(style, thickness) {
    return thickness * (style === "chevron" ? 0.6 : 0.5);
  }

  // The divider's size along the bar, of the bar's separator `style` and
  // `sepThickness` (look.separators; none draws a line): a line or dot's
  // own, a slash's with its lean, a chevron's glyph
  function dividerAlong(thickness, style, sepThickness) {
    const across = root.dividerLength(style, thickness);
    switch (style) {
    case "dot":
      return Math.ceil(sepThickness * 2);
    case "slash":
      return Math.ceil(sepThickness + across * 0.35);
    case "chevron":
      return Math.ceil(across);
    }
    return Math.ceil(sepThickness);
  }

  // What follows the label: a pad, the divider, a pad, then `count` app
  // icons side by side. 0 for none.
  function splitTail(count, thickness, along) {
    if (count <= 0)
      return 0;
    return 2 * root.splitPad(thickness) + along + count * root.iconSize(thickness) + (count - 1) * root.iconGap(thickness);
  }

  // A split cell's whole length along the bar
  function splitLength(label, count, thickness, along) {
    return 2 * root.splitPad(thickness) + label + root.splitTail(count, thickness, along);
  }

  // Where the label's box centre sits from the cell's centre along the bar
  // (negative: towards the start). `label` in splitLength is its ink (the box
  // less `start` and `end`, the margins its icons have), whose centre is the
  // tail's half before the cell's.
  function splitShift(count, thickness, along, start, end) {
    return -root.splitTail(count, thickness, along) / 2 + ((end ?? 0) - (start ?? 0)) / 2;
  }

  // Of `windows` (biggest first), one per app (by app id, a window without
  // one its own), at most `max`: the apps a cell shows
  function distinctApps(windows, max) {
    const seen = [];
    const result = [];
    for (const w of windows ?? []) {
      if (result.length >= max)
        break;
      const key = w.appId ? "app:" + String(w.appId).toLowerCase() : "window:" + w.id;
      if (seen.indexOf(key) >= 0)
        continue;
      seen.push(key);
      result.push(w);
    }
    return result;
  }

  // `windows` in the order they sit on screen off a strip: left to right
  // by their x, then top to bottom (floating ones by their own place)
  function byPosition(windows) {
    return (windows ?? []).map((w, i) => ({
          "w": w,
          "i": i
        })).sort((a, b) => (a.w.x ?? 0) - (b.w.x ?? 0) || (a.w.y ?? 0) - (b.w.y ?? 0) || a.i - b.i).map(e => e.w);
  }

  // The windows whose icons a cell shows in the Row and Square layouts:
  // of `bySize` (biggest first), the biggest `max`, one per app unless
  // `perWindow` (an app by its biggest window), then put in the order of
  // `onScreen` (the same windows as they sit: strip order, or byPosition),
  // an app at its biggest window's place. A window `onScreen` lacks goes
  // after the rest, biggest first
  function chosen(bySize, max, perWindow, onScreen) {
    const picked = perWindow ? (bySize ?? []).slice(0, max) : root.distinctApps(bySize, max);
    const ids = (onScreen ?? []).map(w => w.id);
    const place = w => {
      const at = ids.indexOf(w.id);
      return at < 0 ? ids.length : at;
    };
    return picked.map((w, i) => ({
          "w": w,
          "i": i
        })).sort((a, b) => place(a.w) - place(b.w) || a.i - b.i).map(e => e.w);
  }

  // Where `count` app icons sit in the Square layout, in a square
  // `thickness` across (the middle of a widened cell): [{ x, y, size }],
  // each icon's centre and size as fractions of it. One: a single full
  // icon; two: half-size side by side; three: two over one centred; four
  // or more: a 2×2 block (the first four)
  function squareSlots(count) {
    const half = 0.36;
    const near = 0.3;
    const far = 0.7;
    const slot = (x, y, size) => ({
          "x": x,
          "y": y,
          "size": size
        });
    if (count <= 0)
      return [];
    if (count === 1)
      return [slot(0.5, 0.5, 0.65)];
    if (count === 2)
      return [slot(near, 0.5, half), slot(far, 0.5, half)];
    if (count === 3)
      return [slot(near, near, half), slot(far, near, half), slot(0.5, far, half)];
    return [slot(near, near, half), slot(far, near, half), slot(near, far, half), slot(far, far, half)];
  }

  // The label of one's own for the workspace numbered `number` (the
  // widget's `workspaceLabels`: [{ workspace, show, icon, text }]): {
  // icon, text (each "" where its `show` leaves it out: Icon shows the
  // icon, Text the text, Both both), show }. An entry counts where what
  // it shows isn't empty; with none, both are ""
  function labelFor(entries, number) {
    const parts = e => {
      const show = e?.show ?? "icon";
      return {
        "icon": show !== "text" ? (e?.icon ?? "") : "",
        "text": show !== "icon" ? (e?.text ?? "") : "",
        "show": show
      };
    };
    const entry = (entries ?? []).find(e => {
      const shown = parts(e);
      return e.workspace === number && (shown.icon !== "" || shown.text !== "");
    });
    return parts(entry ?? null);
  }

  // A workspace's compositor `name` where it says more than its id or the
  // number its cell shows, else ""
  function nameShown(name, id, number) {
    const text = (name ?? "").trim();
    return text === "" || text === String(id) || text === String(number) ? "" : text;
  }

  // What a workspace's badge on the overview says: its number (its `id`, or
  // its `place` on the monitor where workspaces are dynamic) or, where the
  // compositor's `name` says more than that, the name
  function badgeText(id, place, name, dynamic) {
    const number = dynamic ? place : id;
    return root.nameShown(name, id, number) || String(number);
  }

  // `windows` (the contract's), the biggest (by area) first, ties in their
  // order
  function bySize(windows) {
    const area = w => (w?.w ?? 0) * (w?.h ?? 0);
    return windows.map((w, i) => ({
          "w": w,
          "i": i
        })).sort((a, b) => area(b.w) - area(a.w) || a.i - b.i).map(e => e.w);
  }

  // What a cell shows, highest first: a label
  // of one's own (`label`), app icons (`icons`, given only for a workspace
  // with windows), the compositor's name (`name`, given only with names
  // on), else its number, dot or nothing: { kind: "text" |
  // "icons" | "name" | "labels", text } (a name is always words, never
  // an icon, where a label of one's own is an icon field's value)
  function pick(label, icons, name) {
    const make = (kind, text) => ({
          "kind": kind,
          "text": text
        });
    if (label !== "")
      return make("text", label);
    if (icons.length > 0)
      return make("icons", "");
    if (name !== "")
      return make("name", name);
    return make("labels", "");
  }
}
