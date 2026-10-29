pragma Singleton
import QtQuick

// The custom widgets' data (docs/dev/features/custom-widgets.md): a script's
// output read as Waybar does (return-type json, or text lines), the fields a
// definition binds, Waybar's format and format-icons, class → theme colour,
// Pango markup → Qt rich text, and the module's element lattice.
QtObject {
  id: root

  // Sub-cells per overlay grid unit on the module lattice (4 units a card,
  // so 16 sub-cells a card)
  readonly property int subCells: 4

  // The fields a definition can bind: Waybar's five, then axiom's
  readonly property var fieldNames: ["text", "alt", "tooltip", "class", "percentage", "icon", "value", "min", "max", "unit", "subtext", "state", "badge", "urgent", "image", "items", "hidden"]

  // Waybar's usual classes → theme colour names (a definition's `states`
  // add to and override these)
  readonly property var defaultStates: ({
      "ok": "success",
      "good": "success",
      "warning": "warning",
      "warn": "warning",
      "critical": "error",
      "error": "error",
      "urgent": "error",
      "info": "info",
      "active": "accent"
    })

  // A sample (an object) from one output: `text` (the trimmed output),
  // `value` (it parsed as JSON, or undefined) and the definition's `format`:
  //   "waybar": a JSON object as is; otherwise lines text, tooltip, class
  //   "json":   a JSON object as is; any other JSON value as { text, value }
  //   "text":   { text }
  // `stream`: each output is one line of a stream (Waybar reads only the
  // text from such a line when it isn't JSON)
  function parse(text, value, format, stream) {
    const isObject = value !== null && typeof value === "object" && !Array.isArray(value);
    if (format !== "text" && isObject)
      return value;
    if (format === "json" && value !== undefined)
      return {
        "text": typeof value === "string" ? value : JSON.stringify(value),
        "value": value
      };
    if (format === "waybar" && !stream) {
      const lines = (text ?? "").split("\n");
      const sample = {
        "text": lines[0] ?? ""
      };
      if (lines.length > 1)
        sample.tooltip = lines[1];
      if (lines.length > 2)
        sample.class = lines[2];
      return sample;
    }
    return {
      "text": text ?? ""
    };
  }

  // The value at a dotted path ("a.b.0.c") in `sample`, or undefined
  function get(sample, path) {
    if (!path)
      return undefined;
    let v = sample;
    for (const part of String(path).split(".")) {
      if (v === null || typeof v !== "object")
        return undefined;
      v = v[part];
    }
    return v;
  }

  // Every path in a sample the editor offers, depth first:
  // [{ path, type ("string", "number", "boolean", "array", "object", "null"),
  //    value (a leaf's value, an array's length) }].
  // An array lists its first `maxItems` (default 3) entries.
  function flatten(sample, maxItems) {
    const out = [];
    const limit = maxItems ?? 3;
    const walk = (v, path, depth) => {
      const type = v === null ? "null" : Array.isArray(v) ? "array" : typeof v;
      if (path)
        out.push({
          "path": path,
          "type": type,
          "value": type === "array" ? v.length : type === "object" ? undefined : v
        });
      if (depth > 6)
        return;
      if (type === "array")
        v.slice(0, limit).forEach((item, i) => walk(item, path ? `${path}.${i}` : String(i), depth + 1));
      else if (type === "object")
        Object.keys(v).forEach(k => walk(v[k], path ? `${path}.${k}` : k, depth + 1));
    };
    walk(sample, "", 0);
    return out;
  }

  // A Waybar format ("{icon} {}", "{text} {percentage}%") filled from
  // `values`: `{}` and `{0}` are the text; `{name}` (a field, or a path in
  // the sample) its value; a `:spec` after the name is ignored. Unknown
  // names fill nothing.
  function fill(template, values) {
    return String(template ?? "").replace(/\{([^{}:]*)(?::[^{}]*)?\}/g, (match, name) => {
      const key = name === "" || name === "0" ? "text" : name;
      const v = key in values ? values[key] : root.get(values._sample, key);
      return v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    });
  }

  // Waybar's format-icons: an array picked by percentage (0-100), an object
  // by alt (else "default"); an object's entry may itself be an array.
  function pickIcon(icons, alt, percentage) {
    if (!icons)
      return "";
    if (typeof icons === "string")
      return icons;
    if (Array.isArray(icons)) {
      if (!icons.length)
        return "";
      const p = Number(percentage);
      const i = isFinite(p) ? Math.floor(p / (100 / icons.length)) : 0;
      return String(icons[Math.max(0, Math.min(icons.length - 1, i))]);
    }
    const entry = (alt !== undefined && alt !== null && String(alt) in icons) ? icons[String(alt)] : icons["default"];
    return entry === undefined ? "" : root.pickIcon(entry, undefined, percentage);
  }

  // A sample's class as a list (Waybar takes a string or an array)
  function classes(value) {
    if (Array.isArray(value))
      return value.map(String).filter(c => c);
    return value ? String(value).split(/\s+/).filter(c => c) : [];
  }

  // The theme colour name for a state: `state` itself when it's a known
  // name or a colour; else the first class `states` (over defaultStates)
  // maps. "" when none.
  function stateColor(state, classList, states) {
    const map = Object.assign({}, root.defaultStates, states ?? {});
    if (state) {
      const s = String(state);
      return map[s] ?? s;
    }
    for (const c of classList ?? []) {
      if (c in map)
        return map[c];
    }
    return "";
  }

  // Text escaped for rich text (Waybar's `escape`)
  function escapeText(text) {
    return String(text ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  // Pango size names → CSS
  readonly property var _sizes: ({
      "xx-small": "xx-small",
      "x-small": "x-small",
      "small": "small",
      "medium": "medium",
      "large": "large",
      "x-large": "x-large",
      "xx-large": "xx-large",
      "smaller": "small",
      "larger": "large"
    })

  // Pango markup → Qt rich text: <span> attributes become CSS (foreground,
  // background, weight, style, size, font family, underline, strikethrough),
  // <b> <i> <u> <s> <tt> <big> <small> <sub> <sup> pass (Qt reads them),
  // newlines become <br>. Anything else passes as text.
  function pango(markup) {
    let s = String(markup ?? "");
    s = s.replace(/<span\b([^>]*)>/g, (m, attrs) => {
      const css = [];
      const re = /([\w-]+)\s*=\s*(?:'([^']*)'|"([^"]*)")/g;
      let a;
      while ((a = re.exec(attrs)) !== null) {
        const name = a[1].replace(/-/g, "_");
        const v = a[2] ?? a[3];
        if (name === "foreground" || name === "fgcolor" || name === "color")
          css.push(`color:${v}`);
        else if (name === "background" || name === "bgcolor")
          css.push(`background-color:${v}`);
        else if (name === "weight" || name === "font_weight")
          css.push(`font-weight:${v === "heavy" || v === "ultrabold" ? "bold" : v === "ultralight" ? "light" : v}`);
        else if (name === "style" || name === "font_style")
          css.push(`font-style:${v}`);
        else if (name === "size" || name === "font_size")
          css.push(`font-size:${root._pangoSize(v)}`);
        else if (name === "font_family" || name === "face")
          css.push(`font-family:'${v}'`);
        else if (name === "underline" && v !== "none")
          css.push("text-decoration:underline");
        else if (name === "strikethrough" && v === "true")
          css.push("text-decoration:line-through");
      }
      return css.length ? `<span style="${css.join(";")}">` : "<span>";
    });
    return s.replace(/\r?\n/g, "<br>");
  }

  function _pangoSize(v) {
    if (v in root._sizes)
      return root._sizes[v];
    if (/^\d+(\.\d+)?pt$/.test(v))
      return v;
    if (/^\d+(\.\d+)?%$/.test(v))
      return v;
    const n = Number(v);
    // A bare number is in 1024ths of a point
    return isFinite(n) && n > 0 ? `${Math.round(n / 1024 * 10) / 10}pt` : "medium";
  }

  // Rich text → plain text (tags dropped, entities read)
  function plain(rich) {
    return String(rich ?? "").replace(/<br\s*\/?>/g, "\n").replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&amp;/g, "&");
  }

  // `text` cut to `max` characters with an ellipsis (max <= 0: as is)
  function truncate(text, max) {
    const s = String(text ?? "");
    return max > 0 && s.length > max ? s.slice(0, Math.max(0, max - 1)) + "…" : s;
  }

  // What one binding gives: "" or absent reads the field's own key in the
  // sample; a binding with a "{" is a format filled from the sample; any
  // other is a path in it
  function bound(sample, key, binding) {
    if (!binding)
      return sample?.[key];
    if (String(binding).indexOf("{") >= 0)
      return root.fill(binding, {
        "_sample": sample,
        "text": sample?.text
      });
    return root.get(sample, binding);
  }

  // The fields of one sample as a definition draws them:
  //   definition: { fields: { <field>: binding }, format, formatIcons,
  //                 states, maxLength, escape, hideEmpty }
  // Returns { text (rich, the format filled), plain (it as plain text),
  // rawText, alt, tooltip (rich), classes, color (a theme name or colour,
  // "" for none), percentage, value, min, max, ratio (0-1, or -1 without a
  // value), unit, subtext, icon (a Material Symbols name), glyph (the
  // format-icons pick), badge, urgent, image, items, hidden, sample }
  function resolve(definition, sample) {
    const d = definition ?? {};
    const s = sample ?? {};
    const f = {};
    for (const key of root.fieldNames)
      f[key] = root.bound(s, key, d.fields?.[key]);
    const num = v => {
      const n = typeof v === "string" ? parseFloat(v) : v;
      return typeof n === "number" && isFinite(n) ? n : undefined;
    };
    const percentage = num(f.percentage);
    let value = num(f.value);
    let min = num(f.min);
    let max = num(f.max);
    if (value === undefined && percentage !== undefined) {
      value = percentage;
      min = min ?? 0;
      max = max ?? 100;
    }
    min = min ?? 0;
    max = max ?? 100;
    const ratio = value === undefined ? -1 : max === min ? 0 : Math.max(0, Math.min(1, (value - min) / (max - min)));
    const str = v => v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    const esc = v => d.escape ? root.escapeText(v) : v;
    const rawText = str(f.text);
    const glyph = root.pickIcon(d.formatIcons, f.alt, percentage ?? (ratio >= 0 ? ratio * 100 : undefined));
    const values = {
      "_sample": s,
      "text": esc(root.truncate(rawText, d.maxLength ?? 0)),
      "icon": glyph,
      "alt": esc(str(f.alt)),
      "percentage": percentage === undefined ? "" : String(Math.round(percentage)),
      "value": value === undefined ? "" : String(value),
      "unit": str(f.unit),
      "subtext": esc(str(f.subtext)),
      "badge": str(f.badge)
    };
    const text = root.pango(root.fill(d.format || "{}", values));
    const textPlain = root.plain(text);
    const classList = root.classes(f.class);
    const items = Array.isArray(f.items) ? f.items.map(i => i !== null && typeof i === "object" ? {
        "text": str(i.text),
        "icon": str(i.icon),
        "value": num(i.value),
        "subtext": str(i.subtext)
      } : {
        "text": str(i),
        "icon": "",
        "value": undefined,
        "subtext": ""
      }) : [];
    const hidden = f.hidden === true || f.hidden === "true" || (d.hideEmpty !== false && rawText === "" && textPlain.trim() === "");
    return {
      "text": text,
      "plain": textPlain,
      "rawText": rawText,
      "alt": str(f.alt),
      "tooltip": root.pango(esc(str(f.tooltip))),
      "classes": classList,
      "color": root.stateColor(str(f.state), classList, d.states),
      "percentage": percentage,
      "value": value,
      "min": min,
      "max": max,
      "ratio": ratio,
      "unit": str(f.unit),
      "subtext": str(f.subtext),
      "icon": str(f.icon),
      "glyph": glyph,
      "badge": str(f.badge),
      "urgent": f.urgent === true || f.urgent === "true" || classList.indexOf("urgent") >= 0,
      "image": str(f.image),
      "items": items,
      "hidden": hidden,
      "sample": s
    };
  }

  // An element's own binding: a format when it has a "{" (filled from the
  // resolved fields, then the sample), else a field name, else a path in
  // the sample. Returns the raw value (a format: its string).
  function elementValue(fields, binding) {
    if (!binding)
      return undefined;
    const b = String(binding);
    if (b.indexOf("{") >= 0) {
      const values = Object.assign({}, fields, {
        "_sample": fields?.sample,
        "text": fields?.plain,
        "icon": fields?.glyph
      });
      return root.fill(b, values);
    }
    if (fields && b in fields && b !== "sample")
      return fields[b];
    return root.get(fields?.sample, b);
  }

  // A number (0-1) between min and max for an element: its value binding
  // read as a number, or the definition's ratio without one. -1: no value.
  function elementRatio(fields, binding, min, max) {
    if (!binding)
      return fields?.ratio ?? -1;
    const v = parseFloat(root.elementValue(fields, binding));
    if (!isFinite(v))
      return -1;
    const lo = isFinite(min) ? min : 0;
    const hi = isFinite(max) ? max : 100;
    return hi === lo ? 0 : Math.max(0, Math.min(1, (v - lo) / (hi - lo)));
  }

  // The module lattice for a design size [w, h] in grid units:
  // { cols, rows } in sub-cells
  function lattice(size) {
    return {
      "cols": Math.max(1, (size?.[0] ?? 4) * root.subCells),
      "rows": Math.max(1, (size?.[1] ?? 2) * root.subCells)
    };
  }

  // An element's rect in px: `place` { x, y, w, h } in sub-cells on a
  // lattice of { cols, rows }, laid over `width` × `height` with `gap`
  // between neighbours (proportional: any size works)
  function rect(place, grid, width, height, gap) {
    const g = gap ?? 0;
    const cw = (width + g) / grid.cols;
    const ch = (height + g) / grid.rows;
    return {
      "x": place.x * cw,
      "y": place.y * ch,
      "width": Math.max(0, place.w * cw - g),
      "height": Math.max(0, place.h * ch - g)
    };
  }

  // Elements moved from one design size to another: places scaled and
  // rounded to the new lattice, kept at least a sub-cell and inside it
  function scaleElements(elements, fromSize, toSize) {
    const a = root.lattice(fromSize);
    const b = root.lattice(toSize);
    return (elements ?? []).map(e => {
      const p = e.place ?? {
        "x": 0,
        "y": 0,
        "w": 1,
        "h": 1
      };
      const w = Math.max(1, Math.min(b.cols, Math.round(p.w * b.cols / a.cols)));
      const h = Math.max(1, Math.min(b.rows, Math.round(p.h * b.rows / a.rows)));
      return Object.assign({}, e, {
        "place": {
          "x": Math.max(0, Math.min(b.cols - w, Math.round(p.x * b.cols / a.cols))),
          "y": Math.max(0, Math.min(b.rows - h, Math.round(p.y * b.rows / a.rows))),
          "w": w,
          "h": h
        }
      });
    });
  }

  // The elements drawn for a definition without any (a module never
  // shows empty): an icon, the text, and a ring when there's a value,
  // filling a lattice of `size`
  function defaultElements(size, hasValue) {
    const g = root.lattice(size);
    const side = Math.max(1, Math.min(g.rows, Math.floor(g.cols / 3)));
    const out = [
      {
        "id": "icon",
        "kind": hasValue ? "Ring" : "Icon",
        "place": {
          "x": 0,
          "y": 0,
          "w": side,
          "h": g.rows
        },
        "bind": {},
        "options": {}
      }
    ];
    if (g.cols - side > 0)
      out.push({
        "id": "text",
        "kind": "Text",
        "place": {
          "x": side,
          "y": 0,
          "w": g.cols - side,
          "h": g.rows
        },
        "bind": {},
        "options": {}
      });
    return out;
  }
}
