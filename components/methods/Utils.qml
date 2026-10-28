pragma Singleton
import QtQuick

// Pure helpers: deep copies, comparison and lookup by path, free ids, usage counts, text width
// and truncation, colors, calendar grids, byte sizes and rates. No file access, processes or
// services (those live in services/).
QtObject {
  id: root

  // A deep copy of plain JSON data (null for undefined): a new object for
  // bindings, or a draft that can be mutated in place
  function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
  }

  // Whether two pieces of plain JSON data are equal, whatever their objects'
  // key order (JSON.stringify compares order too)
  function deepEqual(a, b) {
    if (a === b)
      return true;
    if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
      return false;
    if (Array.isArray(a) !== Array.isArray(b))
      return false;
    if (Array.isArray(a))
      return a.length === b.length && a.every((item, i) => root.deepEqual(item, b[i]));
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every(key => Object.prototype.hasOwnProperty.call(b, key) && root.deepEqual(a[key], b[key]));
  }

  // The value at `path` (an array of keys and indices) in `object`, or
  // undefined where the path runs out: a config value by its key path
  function valueAt(object, path) {
    let value = object;
    for (const key of path)
      value = value?.[key];
    return value;
  }

  // `object` with values laid over it by dotted path ({ "Bars": {...},
  // "Appearance.font.size": 12 }), shallower paths first so a deeper one
  // shows through a whole section laid over it. Only the objects along a
  // path are copied: everything else stays the object it was, and
  // `object` itself is left alone
  function withValuesAt(object, values) {
    const paths = Object.keys(values).sort((a, b) => a.split(".").length - b.split(".").length);
    if (paths.length === 0)
      return object;
    const out = Object.assign({}, object);
    for (const dotted of paths) {
      const path = dotted.split(".");
      let cur = out;
      for (let i = 0; i < path.length - 1; i++) {
        const next = cur[path[i]];
        cur[path[i]] = next !== null && typeof next === "object" && !Array.isArray(next) ? Object.assign({}, next) : {};
        cur = cur[path[i]];
      }
      cur[path[path.length - 1]] = values[dotted];
    }
    return out;
  }

  // A copy of the object `map` with `key` set to `value`, or left out when
  // `value` is undefined: for map properties, whose bindings only update
  // when the property is assigned a new object
  function withEntry(map, key, value) {
    const out = Object.assign({}, map);
    if (value === undefined)
      delete out[key];
    else
      out[key] = value;
    return out;
  }

  // `base` if `taken` doesn't hold it, else its stem (a trailing
  // `separator` + number dropped) numbered from 2: a copy of "dock2" is
  // "dock3", not "dock22"
  function freeId(base, taken, separator = "") {
    if (!taken.includes(base))
      return base;
    const stem = base.replace(new RegExp(separator + "\\d+$"), "");
    let n = 2;
    while (taken.includes(stem + separator + n))
      n++;
    return stem + separator + n;
  }

  // A readable id from a name, as the config conversion makes them:
  // lowercase, other characters as "-" ("Page 2" -> "page-2"), at most 40
  // long; "" when nothing's left
  function slug(name) {
    return String(name ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/, "");
  }

  // A new item's id in `items` (a config list whose items each have one,
  // unique in it): `base` (a type's, lowerCamel: "clockCalendar"), else it
  // numbered from 2 ("clock-2"), as the config conversion names them
  function newId(base, items) {
    const stem = String(base ?? "") === "" ? "item" : String(base)[0].toLowerCase() + String(base).slice(1);
    return root.freeId(stem, (items ?? []).map(item => item?.id), "-");
  }

  // A CamelCase name as words: "SystemTray" -> "System Tray",
  // "Grid2x2" -> "Grid 2x2"
  function spaceWords(name) {
    return String(name ?? "").replace(/([a-zA-Z]{2,})(\d)/g, "$1 $2").replace(/([a-z])([A-Z])/g, "$1 $2");
  }

  // An enum value as English shown text, where the schema gives it no
  // `x-enumLabels`: a lowerCamel word as a sentence ("top" → "Top",
  // "accentText" → "Accent text"); anything else as it is. check_i18n.py
  // makes its keys the same way.
  function enumLabel(value) {
    const text = String(value ?? "");
    if (!/^[a-z][a-zA-Z0-9]*$/.test(text))
      return text;
    const words = root.spaceWords(text).split(" ");
    return [words[0][0].toUpperCase() + words[0].slice(1)].concat(words.slice(1).map(word => /^[A-Z][a-z]/.test(word) ? word.toLowerCase() : word)).join(" ");
  }

  // The Material Symbols arrow pointing at a screen edge ("top", "left", ...)
  function edgeArrow(edge) {
    switch (edge) {
    case "bottom":
      return "arrow_downward";
    case "left":
      return "arrow_back";
    case "right":
      return "arrow_forward";
    }
    return "arrow_upward";
  }

  // `usage` ({ key: { count, last } }) with one more use of `key` at `now`
  // (ms), as a new object so bindings on it update
  function recordUse(usage, key, now) {
    const entry = usage?.[key] ?? {
      "count": 0,
      "last": 0
    };
    const updated = Object.assign({}, usage);
    updated[key] = {
      "count": entry.count + 1,
      "last": now
    };
    return updated;
  }

  function charWidth(codePoint) {
    return ((codePoint >= 0x1100 && codePoint <= 0x115F) || codePoint === 0x2329 || codePoint === 0x232A || (codePoint >= 0x2E80 && codePoint <= 0xA4CF && codePoint !== 0x303F) || (codePoint >= 0xAC00 && codePoint <= 0xD7A3) || (codePoint >= 0xF900 && codePoint <= 0xFAFF) || (codePoint >= 0xFE30 && codePoint <= 0xFE6F) || (codePoint >= 0xFF00 && codePoint <= 0xFF60) || (codePoint >= 0xFFE0 && codePoint <= 0xFFE6) || (codePoint >= 0x20000 && codePoint <= 0x3FFFD)) ? 2 : 1;
  }

  function visualWidth(text) {
    let width = 0;
    for (const ch of text)
      width += charWidth(ch.codePointAt(0));
    return width;
  }

  function truncate(text, maxLength, ellipsis = "...") {
    const fullWidth = visualWidth(text);
    if (fullWidth <= maxLength)
      return text;

    const ellipsisWidth = visualWidth(ellipsis);
    const budget = maxLength - ellipsisWidth;

    let width = 0;
    let result = "";
    for (const ch of text) {
      const w = charWidth(ch.codePointAt(0));
      if (width + w > budget)
        break;
      result += ch;
      width += w;
    }
    return result + ellipsis;
  }

  readonly property real bytesPerGiB: 1073741824

  // A transfer rate as [value, unit]: "B/s" to "GB/s", one decimal under
  // 10 (past bytes), e.g. [1.5, "MB/s"], [512, "KB/s"]
  function rateParts(bytesPerSecond) {
    const units = ["B/s", "KB/s", "MB/s", "GB/s"];
    let value = Math.max(0, bytesPerSecond || 0);
    let i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return [value < 10 && i > 0 ? Number(value.toFixed(1)) : Math.round(value), units[i]];
  }

  // "1.5 MB/s"
  function formatRate(bytesPerSecond) {
    return root.rateParts(bytesPerSecond).join(" ");
  }

  // A disk size: whole GiB ("512G"), or TiB with one decimal from 1000 GiB
  // ("1.8T")
  function formatSize(bytes) {
    const gib = bytes / root.bytesPerGiB;
    return gib >= 1000 ? `${(gib / 1024).toFixed(1)}T` : `${Math.round(gib)}G`;
  }

  // A file size in binary units, one decimal under 10 ("820 B", "4.2 MiB",
  // "37 MiB", "1.3 GiB")
  function formatBytes(bytes) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB"];
    let value = Math.max(0, Number(bytes) || 0);
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    const shown = unit === 0 || value >= 10 ? String(Math.round(value)) : value.toFixed(1);
    return shown + " " + units[unit];
  }

  // A colour to animate to or from: a fully transparent `c` becomes the
  // first visible one of `fallbacks` at alpha 0, since fading through
  // "transparent" (transparent black) flashes dark mid-animation
  function fadeable(c, ...fallbacks) {
    if (Qt.color(c).a > 0)
      return c;
    const visible = fallbacks.find(f => Qt.color(f).a > 0);
    return visible !== undefined ? Qt.alpha(visible, 0) : c;
  }

  // Check if color is dark
  function isColorDark(color) {
    const c = Qt.color(color);
    const luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    return luminance < 0.5;
  }

  // Get contrasting text color for background
  function getContrastColor(backgroundColor) {
    return isColorDark(backgroundColor) ? "#FFFFFF" : "#000000";
  }

  // The 6 weeks (42 days) shown for a month, starting on `firstDay` (0 =
  // Sunday, as Date.getDay()): [{ day, month, year, inMonth, isToday, key }]
  // (key: "YYYY-MM-DD", as CalendarEvents.dayKey).
  // `today` is a date string (Date.toDateString()), so callers can bind
  // it to something that only changes once a day.
  function monthGrid(year, month, firstDay, today) {
    const first = new Date(year, month, 1);
    const start = new Date(year, month, 1 - ((first.getDay() - firstDay + 7) % 7));
    const days = [];
    for (let i = 0; i < 42; i++) {
      const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
      days.push({
        "day": d.getDate(),
        "month": d.getMonth(),
        "year": d.getFullYear(),
        "inMonth": d.getMonth() === month,
        "isToday": d.toDateString() === today,
        "key": d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
      });
    }
    return days;
  }

  // [start, end] with `spans` ([{ start, end }], any order, may overlap or
  // reach past it) taken out: the pieces left, in order, as { start, end }
  function subtractSpans(start, end, spans) {
    const cuts = spans.filter(span => span.end > start && span.start < end).sort((a, b) => a.start - b.start);
    const pieces = [];
    let at = start;
    for (const cut of cuts) {
      if (cut.start > at)
        pieces.push({
          "start": at,
          "end": cut.start
        });
      at = Math.max(at, cut.end);
    }
    if (at < end)
      pieces.push({
        "start": at,
        "end": end
      });
    return pieces;
  }
}
