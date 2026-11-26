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

  // `object` with only `keys` (those it has), in their order
  function pick(object, keys) {
    return (keys ?? []).reduce((out, key) => {
      if (object && key in object)
        out[key] = object[key];
      return out;
    }, {});
  }

  // Whether `value` is plain data: an object that is not null, not an array
  // and has Object.prototype (not a Qt value type or a class), and is a plain
  // JS object (a QObject wrapper also has Object.prototype)
  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype && Object.prototype.toString.call(value) === "[object Object]";
  }

  // Whether two pieces of data are equal, whatever their objects' key order
  // (JSON.stringify compares order too). Plain JSON and value types
  // (Qt.rect, Qt.point, colours) are walked; a QObject (a window, an Item)
  // is equal only to itself.
  function deepEqual(a, b) {
    if (a === b)
      return true;
    if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
      return false;
    const qobject = x => x !== null && typeof x === "object" && !Array.isArray(x) && !root.isPlainObject(x) && typeof x.objectName === "string";
    if (qobject(a) || qobject(b))
      return false;
    if (Array.isArray(a) !== Array.isArray(b))
      return false;
    if (Array.isArray(a))
      return a.length === b.length && a.every((item, i) => root.deepEqual(item, b[i]));
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every(key => Object.prototype.hasOwnProperty.call(b, key) && root.deepEqual(a[key], b[key]));
  }

  // `fresh` (an array of entries, `idOf(entry)` their ids) with each entry
  // equal to the one of the same id in `prev` replaced by that previous
  // object, so a rebuilt list of equal content notifies no reader. `prev` is
  // { items, keys } from the last call; returns { items, keys } (keys[i] is
  // JSON.stringify(fresh[i])), `items` being `prev.items` itself when
  // nothing changed. Entries are plain data and colours (a QColor
  // serialises as r/g/b/a); functions would be dropped from the key.
  function keepEqual(prev, fresh, idOf) {
    const oldKeys = new Map();
    (prev?.items ?? []).forEach((item, i) => oldKeys.set(idOf(item), {
        "item": item,
        "key": prev.keys[i]
      }));
    const keys = fresh.map(entry => JSON.stringify(entry));
    let kept = 0;
    const items = fresh.map((entry, i) => {
      const old = oldKeys.get(idOf(entry));
      if (old && old.key === keys[i]) {
        kept++;
        return old.item;
      }
      return entry;
    });
    const same = prev?.items && prev.items.length === items.length && kept === items.length && items.every((item, i) => item === prev.items[i]);
    return {
      "items": same ? prev.items : items,
      "keys": keys
    };
  }

  // The value at `path` (an array of keys and indices) in `object`, or
  // undefined where the path runs out: a config value by its key path
  function valueAt(object, path) {
    let value = object;
    for (const key of path)
      value = value?.[key];
    return value;
  }

  // The index of a form's top row (FormRow.first): FormRows.first over the
  // `count` rows `rowAt(i)` gives (a Repeater's itemAt; null where missing);
  // -1 for none
  function firstFormRow(count, rowAt) {
    return FormRows.first(Array.from({
      length: count
    }, (_, i) => rowAt(i)));
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

  // Whether `text` is one or more Material Symbols names ("wifi"), which
  // StyledIcon draws as icons, not a glyph or words drawn in the text font
  function isSymbolName(text) {
    return /^\s*[a-z][a-z0-9_]*(\s+[a-z][a-z0-9_]*)*\s*$/.test(text ?? "");
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

  // A config alignment ("left" | "center" | "right") as Text's horizontalAlignment
  function horizontalAlignment(alignment) {
    switch (alignment) {
    case "left":
      return Text.AlignLeft;
    case "right":
      return Text.AlignRight;
    }
    return Text.AlignHCenter;
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

  // A 64th of a px (a power of two, exact in float): how far an edge is
  // drawn in so it never lands on a device pixel's centre at a fractional
  // scale, where Qt rounds a clip edge .5 up (HoledCopy's holes) and a
  // CurveRenderer stroke gives the pixel its full coverage (AttachedSurface's
  // outline)
  readonly property real tieInset: 1 / 64

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

  // A sensor's °C in `units` ("celsius" | "fahrenheit", as
  // TemperatureUnits resolved by WeatherConfig.unitsOf)
  function fromCelsius(celsius, units) {
    return units === "fahrenheit" ? celsius * 9 / 5 + 32 : celsius;
  }

  // The unit text of `units`: "°C" or "°F"
  function temperatureSymbol(units) {
    return units === "fahrenheit" ? "°F" : "°C";
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

  // `bounds` (a rect) with `rects` (any order, may overlap or reach past it)
  // taken out: disjoint rects covering the rest, row by row (cut at every
  // top and bottom of `rects` inside `bounds`; in each row, the x-spans
  // left by subtractSpans). [] when nothing is left, [bounds] when nothing
  // is taken. Reads x, y, width and height; returns Qt.rects.
  function subtractRects(bounds, rects) {
    const top = bounds.y, bottom = bounds.y + bounds.height;
    const inside = rects.filter(r => r.width > 0 && r.height > 0 && r.y + r.height > top && r.y < bottom && r.x + r.width > bounds.x && r.x < bounds.x + bounds.width);
    if (inside.length === 0)
      return bounds.width > 0 && bounds.height > 0 ? [Qt.rect(bounds.x, bounds.y, bounds.width, bounds.height)] : [];
    const edges = [top, bottom];
    for (const r of inside) {
      edges.push(Math.max(top, Math.min(bottom, r.y)), Math.max(top, Math.min(bottom, r.y + r.height)));
    }
    const ys = edges.filter((y, i) => edges.indexOf(y) === i).sort((a, b) => a - b);
    const pieces = [];
    for (let i = 0; i + 1 < ys.length; i++) {
      const y0 = ys[i], y1 = ys[i + 1];
      const row = inside.filter(r => r.y < y1 && r.y + r.height > y0).map(r => ({
            "start": r.x,
            "end": r.x + r.width
          }));
      for (const span of root.subtractSpans(bounds.x, bounds.x + bounds.width, row))
        pieces.push(Qt.rect(span.start, y0, span.end - span.start, y1 - y0));
    }
    return pieces;
  }

  // The part of `bounds` that `rects` cover (subtractRects' rects), drawn in
  // by `by` on every edge it has against the rest of `bounds`; edges where
  // two of `rects` meet stay where they are. Disjoint Qt.rects, [] when
  // nothing is covered.
  function insetUnion(bounds, rects, by) {
    const rest = root.subtractRects(bounds, rects).map(r => Qt.rect(r.x - by, r.y - by, r.width + by * 2, r.height + by * 2));
    return root.subtractRects(bounds, rest);
  }

  // `bounds` less `holes` (rects, same coordinates), the holes' outer edges
  // drawn in by tieInset so a pixel centred on a hole's edge stays the
  // drawing's: subtractRects, but for that inset. Disjoint Qt.rects.
  function subtractHoles(bounds, holes) {
    return root.subtractRects(bounds, root.insetUnion(bounds, holes, root.tieInset));
  }
}
