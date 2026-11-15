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
  readonly property var fieldNames: ["text", "alt", "tooltip", "class", "percentage", "icon", "value", "min", "max", "unit", "subtext", "state", "badge", "urgent", "image", "items", "hidden", "rev", "actions", "error"]

  // Waybar's usual classes → theme colour names (an element's or the bar's
  // Auto colour follows these)
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
  // `value` (it parsed as JSON, or undefined) and the definition's `format`.
  // "waybar" and "json" are both Auto:
  //   a JSON object: as it is
  //   a JSON array: { text: its length, value: its length, items: the array }
  //   any other JSON value: { text: String(v), value: v }
  //   not JSON: Waybar's lines (text, tooltip, class), or only the text for
  //             a stream line
  //   "text":   { text }, the JSON ignored
  function parse(text, value, format, stream) {
    if (format === "text")
      return {
        "text": text ?? ""
      };
    if (value !== null && typeof value === "object" && !Array.isArray(value))
      return value;
    if (Array.isArray(value))
      return {
        "text": String(value.length),
        "value": value.length,
        "items": value
      };
    if (value !== undefined)
      return {
        "text": String(value),
        "value": value
      };
    if (stream)
      return {
        "text": text ?? ""
      };
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

  // A value as text: "" for nothing, JSON for an object or list
  function asText(v) {
    return v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
  }

  // A list of rows (an output's items, or a bound list) as
  // { text, icon, value (a number, or undefined), subtext, id, state (its
  // tone's word), max (a number above 0 that a numeric value is out of, else
  // undefined: the row draws a meter), image (a path or URL), raw (the
  // item) }: a plain entry is its text, the rest empty; anything not a list
  // is none. `map` (a List's `row`: { text, subtext, icon, id }, each typed
  // text or {key} of the item, a path reaching into it) says where those four
  // come from; without it each is the item's key of that name.
  function rows(v, map) {
    if (!Array.isArray(v))
      return [];
    return v.map(i => {
      if (i === null || typeof i !== "object")
        return {
          "text": root.asText(i),
          "icon": "",
          "value": undefined,
          "subtext": "",
          "id": "",
          "state": "",
          "max": undefined,
          "image": "",
          "raw": i
        };
      const value = root._number(i.value);
      const max = root._number(i.max);
      const own = key => map ? root._rowText(map[key], i) : root.asText(i[key]);
      return {
        "text": own("text"),
        "icon": own("icon"),
        "value": value,
        "subtext": own("subtext"),
        "id": own("id"),
        "state": root.asText(i.state),
        "max": value !== undefined && max !== undefined && max > 0 ? max : undefined,
        "image": root.asText(i.image),
        "raw": i
      };
    });
  }

  // A row-mapping field against a row: typed text as it is, {key} (one, alone)
  // the row's value of it, else the text filled; a key the row lacks is empty
  function _rowText(template, item) {
    const t = String(template ?? "");
    if (t.indexOf("{") < 0)
      return t;
    const one = /^\{([^{}:]*)\}$/.exec(t);
    if (one)
      return root.asText(root.get(item, one[1] === "" || one[1] === "0" ? "text" : one[1]));
    return root.fill(t, {
      "_sample": item
    });
  }

  // A number, or one in a string; undefined otherwise
  function _number(v) {
    const n = typeof v === "string" ? parseFloat(v) : v;
    return typeof n === "number" && isFinite(n) ? n : undefined;
  }

  // The value at a dotted path ("a.b.0.c") in `sample`, or undefined
  function get(sample, path) {
    return path ? Utils.valueAt(sample, String(path).split(".")) : undefined;
  }

  // Every path in a sample the editor offers, depth first:
  // [{ path, type ("string", "number", "boolean", "array", "object", "null"),
  //    value (a leaf's value, an array's length) }].
  // An array lists its first `maxItems` (default 50) entries.
  function flatten(sample, maxItems) {
    const out = [];
    const limit = maxItems ?? 50;
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
  // With `keepUnknown` a name that is no field and no path stays as typed.
  function fill(template, values, keepUnknown) {
    return String(template ?? "").replace(/\{([^{}:]*)(?::[^{}]*)?\}/g, (match, name) => {
      const key = name === "" || name === "0" ? "text" : name;
      const known = key in values;
      const v = known ? values[key] : root.get(values._sample, key);
      return keepUnknown && !known && v === undefined ? match : root.asText(v);
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

  // Whether `name` is one of the theme's colour names (`colorNames`, the
  // keys of Theme.stringToColorMap)
  function isThemeColor(name, colorNames) {
    return (colorNames ?? []).indexOf(String(name)) >= 0;
  }

  // The theme colour name for a state. The first that holds: defaultStates
  // maps `state`; `state` is itself a theme colour name; the first class
  // defaultStates maps. "" when none: a state that is neither mapped nor a
  // theme name (a hex too) colours nothing.
  function stateColor(state, classList, colorNames) {
    const map = root.defaultStates;
    const mapped = key => Object.prototype.hasOwnProperty.call(map, key);
    if (state) {
      const s = String(state);
      if (mapped(s))
        return map[s];
      if (root.isThemeColor(s, colorNames))
        return s;
    }
    for (const c of classList ?? []) {
      if (mapped(c))
        return map[c];
    }
    return "";
  }

  // Whether a script's value counts as on: true, a non-zero number, a string
  // that isn't "", false, 0, no or off (any case), a non-empty list or object
  function truthy(v) {
    if (v === true)
      return true;
    if (typeof v === "number")
      return isFinite(v) && v !== 0;
    if (typeof v === "string")
      return ["", "false", "0", "no", "off"].indexOf(v.trim().toLowerCase()) < 0;
    if (Array.isArray(v))
      return v.length > 0;
    return v !== null && typeof v === "object" && Object.keys(v).length > 0;
  }

  // An action id (a letter, digit, "_", "." or "-", up to 64; "axiom:" ids
  // are the shell's own)
  function _actionId(id) {
    return /^[A-Za-z0-9_.-]{1,64}$/.test(id);
  }

  // A sample's `actions` ({<id>: {enabled}}) as { <id>: { enabled } }, or
  // null when it isn't an object (no list: every action is on). Ids that
  // aren't action ids, and `axiom:` ids (always on), are dropped; `enabled`
  // is truthy, and on when missing.
  function actionsOf(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value))
      return null;
    const out = {};
    for (const id of Object.keys(value)) {
      // names every object has (`__proto__`, `constructor`, …) aren't action ids
      if (!root._actionId(id) || id in Object.prototype)
        continue;
      const entry = value[id];
      out[id] = {
        "enabled": root.truthy(entry !== null && typeof entry === "object" ? entry.enabled ?? true : true)
      };
    }
    return out;
  }

  // `template` with {0}, {1}… filled from `args`
  function _format(template, args) {
    return String(template ?? "").replace(/\{(\d+)\}/g, (m, i) => i in args ? String(args[i]) : m);
  }

  // Why a definition's script isn't answering, or null: { kind, message,
  // exitCode, stderr }. Only an interactive definition fails (a Waybar-style
  // one draws as it always did). `run` is the script's last run { exitCode,
  // error, stderr, text, exited }; `context` { interactive, stream, words:
  // { exited, exitedWith } } (the two message templates, {0} the code and
  // {1} the stderr line). The first that holds:
  //   start:   it couldn't start (exitCode -1 and an error)
  //   stopped: a stream that ended with a non-zero exit
  //   exit:    a non-zero exit with no output
  //   script:  the sample's own `error` (a non-empty string, or any other
  //            truthy value)
  function failure(sample, run, context) {
    if (!context?.interactive)
      return null;
    const r = run ?? {};
    const words = context.words ?? {};
    const code = typeof r.exitCode === "number" ? r.exitCode : undefined;
    const stderr = r.stderr ? String(r.stderr) : "";
    const make = (kind, message) => ({
          "kind": kind,
          "message": message,
          "exitCode": code ?? 0,
          "stderr": stderr
        });
    const exitMessage = () => stderr ? root._format(words.exitedWith, [code, stderr]) : root._format(words.exited, [code]);
    if (code === -1 && r.error)
      return make("start", String(r.error));
    if (context.stream && r.exited && code !== undefined && code !== 0)
      return make("stopped", exitMessage());
    if (code !== undefined && code !== 0 && !r.text)
      return make("exit", exitMessage());
    const e = sample?.error;
    const error = typeof e === "string" ? e.trim() : root.truthy(e) ? root.asText(e) : "";
    return error !== "" ? make("script", error) : null;
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

  // The fields of one sample as a definition draws them, each read from
  // the key of the same name (a script shapes its own JSON). Plain text
  // that's a number is the value; text matching a format-icons key is the
  // alt (so a script printing "on" picks the "on" icon); a format-icons
  // pick that's a Material Symbols name is the icon, when there's none.
  //   definition: { format, formatIcons,
  //                 maxLength, escape, hideEmpty }
  // Returns { text (rich, the format filled), plain (it as plain text),
  // rawText, alt, tooltip (rich), classes, color (a theme colour name,
  // "" for none), percentage, value, min, max (0-100 unless given), hasMax
  // (the output gave a max or a percentage), ratio (0-1, or -1 without a
  // value), state, rev, actions (actionsOf), failure (failure), error (its
  // message), hiddenByScript (the output's own `hidden`), interactive and
  // colorNames (the context's), unit, subtext, icon (a Material Symbols name), glyph (the
  // format-icons pick), badge, urgent, image, items, hidden, sample }
  function resolve(definition, sample, context) {
    const d = definition ?? {};
    const s = sample ?? {};
    const f = {};
    for (const key of root.fieldNames)
      f[key] = s[key];
    const num = root._number;
    const percentage = num(f.percentage);
    const textNumber = typeof f.text === "string" && /^\s*-?\d+(\.\d+)?\s*%?\s*$/.test(f.text) ? parseFloat(f.text) : undefined;
    let value = num(f.value) ?? (percentage === undefined ? textNumber : undefined);
    const icons = d.formatIcons;
    if ((f.alt === undefined || f.alt === null) && icons && typeof icons === "object" && !Array.isArray(icons) && typeof f.text === "string" && f.text.trim() in icons)
      f.alt = f.text.trim();
    let min = num(f.min);
    let max = num(f.max);
    // The output says how far the value goes (a max, or a percentage)
    const hasMax = max !== undefined || (value === undefined && percentage !== undefined);
    if (value === undefined && percentage !== undefined) {
      value = percentage;
      min = min ?? 0;
      max = max ?? 100;
    }
    min = min ?? 0;
    max = max ?? 100;
    const ratio = value === undefined ? -1 : max === min ? 0 : Math.max(0, Math.min(1, (value - min) / (max - min)));
    const str = root.asText;
    const esc = v => d.escape ? root.escapeText(v) : v;
    const rawText = str(f.text);
    const glyph = root.pickIcon(d.formatIcons, f.alt, percentage ?? (ratio >= 0 ? ratio * 100 : undefined));
    const values = {
      "_sample": s,
      "text": esc(d.maxLength > 0 ? Utils.truncate(rawText, d.maxLength, "…") : rawText),
      "icon": glyph,
      "alt": esc(str(f.alt)),
      "percentage": percentage === undefined ? "" : String(Math.round(percentage)),
      "value": value === undefined ? "" : String(value),
      "unit": str(f.unit),
      "subtext": esc(str(f.subtext)),
      "badge": str(f.badge)
    };
    // A Material Symbols name picked from format-icons draws as the icon
    if (!f.icon && /^[a-z][a-z0-9_]*$/.test(glyph))
      f.icon = glyph;
    const text = root.pango(root.fill(d.format || "{}", values));
    const textPlain = root.plain(text);
    const classList = root.classes(f.class);
    const items = root.rows(f.items);
    const hiddenByScript = f.hidden === true || f.hidden === "true";
    const failure = root.failure(s, context?.run, context);
    // A failing widget always shows its failure
    const hidden = failure === null && (hiddenByScript || (d.hideEmpty !== false && rawText.trim() === ""));
    return {
      "text": text,
      "plain": textPlain,
      "rawText": rawText,
      "alt": str(f.alt),
      "tooltip": root.pango(esc(str(f.tooltip))),
      "classes": classList,
      "color": root.stateColor(str(f.state), classList, context?.colorNames),
      "state": str(f.state),
      "rev": str(f.rev),
      "actions": root.actionsOf(f.actions),
      "failure": failure,
      "error": failure?.message ?? "",
      "interactive": !!context?.interactive,
      "colorNames": context?.colorNames ?? [],
      "hiddenByScript": hiddenByScript,
      "percentage": percentage,
      "value": value,
      "min": min,
      "max": max,
      "hasMax": hasMax,
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

  // What resolve returns for its own use, not an output key of that name: a
  // binding of one reads the sample's
  readonly property var _internalFields: ["colorNames", "actions", "interactive", "failure"]

  // What a text field of an element reads as (an element's `bind`): "" is
  // nothing (undefined: the slot falls back to the output's own key); exactly
  // one {path} alone is the value itself (a field of `fields`, else a path in
  // the sample: a list, a number, text; undefined when missing); other text
  // with a "{" is filled ({text} is the plain text; a {x} that is no field and
  // no path stays as typed); anything else is typed text, a number when it is one.
  function elementValue(fields, binding) {
    if (binding === undefined || binding === null || binding === "")
      return undefined;
    const b = String(binding);
    const one = /^\{([^{}:]*)\}$/.exec(b);
    if (one) {
      const key = one[1] === "" || one[1] === "0" ? "text" : one[1];
      if (key === "text" && fields)
        return fields.plain;
      // `sample` and resolve's own bookkeeping aren't fields a script prints
      if (fields && key in fields && key !== "sample" && root._internalFields.indexOf(key) < 0)
        return fields[key];
      return root.get(fields?.sample, key);
    }
    if (b.indexOf("{") >= 0) {
      const values = Object.assign({}, fields, {
        "_sample": fields?.sample,
        "text": fields?.plain,
        "icon": fields?.glyph
      });
      for (const key of root._internalFields)
        delete values[key];
      return root.fill(b, values, true);
    }
    return /^-?\d+(\.\d+)?$/.test(b.trim()) ? Number(b) : b;
  }

  // The {paths} of a text field that read nothing in `fields` (no field, no
  // path in the sample): what the editor warns about
  function unknownPaths(fields, binding) {
    const out = [];
    const re = /\{([^{}:]*)(?::[^{}]*)?\}/g;
    let m;
    while ((m = re.exec(String(binding ?? ""))) !== null) {
      const key = m[1] === "" || m[1] === "0" ? "text" : m[1];
      const field = key === "text" || (fields && key in fields && key !== "sample" && root._internalFields.indexOf(key) < 0);
      if (!field && root.get(fields?.sample, key) === undefined && out.indexOf(key) < 0)
        out.push(key);
    }
    return out;
  }

  // An element's slot as the element reads it: its text field when typed,
  // else the output's own `slot` (an unbound text shows the output's text)
  function ownValue(fields, bind, slot) {
    return bind?.[slot] ? root.elementValue(fields, bind[slot]) : fields?.[slot];
  }

  // Whether `value` passes a test (a colour rule's, or an element's Visible):
  //   is / isNot: the text of the value, trimmed, against `operand`
  //   above / below: both as numbers (parseFloat, so "85%" is 85); false
  //                  when either isn't one
  //   set / unset: has a value (text counts, even "0"), then not
  //   always: true
  function holds(test, value, operand) {
    switch (test) {
    case "always":
      return true;
    case "is":
      return root.asText(value).trim() === String(operand ?? "").trim();
    case "isNot":
      return root.asText(value).trim() !== String(operand ?? "").trim();
    case "above":
    case "below":
      {
        const v = parseFloat(root.asText(value));
        const o = parseFloat(operand);
        if (isNaN(v) || isNaN(o))
          return false;
        return test === "above" ? v > o : v < o;
      }
    case "set":
      return root._isSet(value);
    case "unset":
      return !root._isSet(value);
    }
    return false;
  }

  // Whether a value is set: text (even "0" or "no") when it isn't empty,
  // else truthy (not 0, false, nothing or an empty list)
  function _isSet(value) {
    return typeof value === "string" ? value.trim() !== "" : root.truthy(value);
  }

  // What a colour rule or Visible reads: `key` "" is `own` (what the element
  // shows), else the key or path in the output ({key} through elementValue)
  function readKey(fields, key, own) {
    return key ? root.elementValue(fields, "{" + key + "}") : own;
  }

  // A colour as a name ("" for Auto): with `states.enabled` the colour of the
  // first rule that holds (its own "" is `auto`); else, or when none holds,
  // `picked`, else `auto`. A hex passes as it is
  function colorFor(picked, states, fields, own, auto) {
    if (states?.enabled) {
      const value = root.readKey(fields, states.key, own);
      for (const rule of states.rules ?? []) {
        if (root.holds(rule.test, value, rule.value))
          return rule.color || auto;
      }
    }
    return picked || auto;
  }

  // colorFor over a List row: the key is read from the row's own item
  // (`row.raw`, a path as {key}), "" reads its text
  function rowColor(picked, states, row) {
    const own = row?.text;
    if (!states?.enabled)
      return picked || "";
    const value = states.key ? root.get(row?.raw, states.key) : own;
    for (const rule of states.rules ?? []) {
      if (root.holds(rule.test, value, rule.value))
        return rule.color || "";
    }
    return picked || "";
  }

  // Whether an element is shown (its showWhen: { test, key, value }): always
  // when there is none
  function shown(showWhen, fields, own) {
    const test = showWhen?.test ?? "always";
    return test === "always" || root.holds(test, root.readKey(fields, showWhen.key, own), showWhen.value);
  }

  // The colours of a kind's options schema, in `order`: { colors: [{ key,
  // statesKey }] (a key with `x-options: colors`; statesKey `<key>States`
  // when the schema has it, else ""), look: the other keys, the `…States`
  // ones left out }
  function colorFields(options, order) {
    const keys = (order ?? []).length > 0 ? order : Object.keys(options ?? {});
    const colors = [];
    const look = [];
    for (const key of keys) {
      const states = key + "States";
      if (options?.[key]?.["x-options"] === "colors")
        colors.push({
          "key": key,
          "statesKey": options?.[states] ? states : ""
        });
      else if (!(key.endsWith("States") && options?.[key.slice(0, -6)]?.["x-options"] === "colors"))
        look.push(key);
    }
    return {
      "colors": colors,
      "look": look
    };
  }

  // An element's value, min and max as numbers: each slot's binding (a
  // field, a path, a format or a number), else the widget's own value,
  // min and max (the script's, 0-100 for a percentage)
  function elementRange(fields, bind) {
    const num = (slot, own) => {
      const b = bind?.[slot];
      const v = b ? parseFloat(root.elementValue(fields, b)) : own;
      return typeof v === "number" && isFinite(v) ? v : undefined;
    };
    return {
      "value": num("value", fields?.value),
      "min": num("min", fields?.min) ?? 0,
      "max": num("max", fields?.max) ?? 100
    };
  }

  // The range a graph of an element's value is drawn over (a Sparkline,
  // the bar's sparkline style): min and max as elementRange, except a max
  // neither bound nor given by the output (resolve's hasMax) is 0,
  // scaling to the largest value
  function graphRange(fields, bind) {
    const r = root.elementRange(fields, bind);
    const given = !!bind?.max || fields?.hasMax === true;
    return {
      "min": r.min,
      "max": given ? r.max : 0
    };
  }

  // 0-1 for an element (elementRange), -1 without a value
  function elementRatio(fields, bind) {
    const r = root.elementRange(fields, bind);
    if (r.value === undefined)
      return -1;
    return r.max === r.min ? 0 : Math.max(0, Math.min(1, (r.value - r.min) / (r.max - r.min)));
  }

  // JSONC (a Waybar config: // and /* */ comments, trailing commas) as
  // JSON text
  function stripJsonc(text) {
    const src = String(text ?? "");
    let out = "";
    let inString = false;
    for (let i = 0; i < src.length; i++) {
      const c = src[i];
      if (inString) {
        out += c;
        if (c === "\\") {
          out += src[i + 1] ?? "";
          i++;
        } else if (c === "\"") {
          inString = false;
        }
      } else if (c === "\"") {
        inString = true;
        out += c;
      } else if (c === "/" && src[i + 1] === "/") {
        while (i < src.length && src[i] !== "\n")
          i++;
        out += "\n";
      } else if (c === "/" && src[i + 1] === "*") {
        i += 2;
        while (i < src.length && !(src[i] === "*" && src[i + 1] === "/"))
          i++;
        i++;
      } else {
        out += c;
      }
    }
    return out.replace(/,(\s*[}\]])/g, "$1");
  }

  // A Waybar module's name ("custom/media") as a definition's name ("Media")
  function waybarName(name) {
    const base = String(name ?? "").replace(/^custom\//, "").replace(/[-_#]+/g, " ").trim();
    return base ? base[0].toUpperCase() + base.slice(1) : "Custom widget";
  }

  // Waybar custom module config → partial definitions (no ids). `text` is
  // pasted from a Waybar config: one block `"custom/x": { … }` (with or
  // without its braces around it), a bare `{ "exec": … }`, or a whole
  // config, whose custom/* modules each become one. Throws on text that
  // isn't JSON(C).
  //   exec → command; interval (s) → poll, "once" → once, none → stream;
  //   exec-if, format, format-icons, max-length, escape, tooltip,
  //   on-click(-right, -middle), on-scroll-up/down (each an action that
  //   doesn't wait, run by the bar's click or scroll: bar.run); signal →
  //   refreshName
  function fromWaybar(text) {
    let body = root.stripJsonc(text).trim();
    if (/^"[^"]+"\s*:/.test(body))
      body = "{" + body + "}";
    const parsed = JSON.parse(body);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed))
      throw new Error("not a Waybar module");
    const modules = "exec" in parsed ? [["custom/script", parsed]] : Object.keys(parsed).filter(k => /^custom\//.test(k) && parsed[k] && typeof parsed[k] === "object").map(k => [k, parsed[k]]);
    return modules.map(([name, m]) => {
      const interval = m.interval;
      const def = {
        "name": root.waybarName(name),
        "command": String(m.exec ?? ""),
        "mode": interval === "once" ? "once" : typeof interval === "number" && interval > 0 ? "poll" : "stream",
        "output": "waybar",
        "format": typeof m.format === "string" ? m.format : "{}",
        "actions": {
          "items": []
        }
      };
      if (def.mode === "poll")
        def.interval = Math.max(500, Math.round(interval * 1000));
      if (m["exec-if"])
        def.execIf = String(m["exec-if"]);
      if (m["format-icons"] !== undefined)
        def.formatIcons = m["format-icons"];
      if (typeof m["max-length"] === "number")
        def.maxLength = m["max-length"];
      if (m.escape === true)
        def.escape = true;
      if (m.tooltip === false)
        def.tooltip = false;
      if (m.signal !== undefined)
        def.refreshName = String(name).replace(/^custom\//, "");
      // Each click or scroll command becomes an action (named by its
      // trigger: I18n.tr("Click") I18n.tr("Right click") I18n.tr("Middle click")
      // I18n.tr("Scroll up") I18n.tr("Scroll down")) the bar runs
      const triggers = {
        "on-click": ["click", "Click"],
        "on-click-right": ["rightClick", "Right click"],
        "on-click-middle": ["middleClick", "Middle click"],
        "on-scroll-up": ["scrollUp", "Scroll up"],
        "on-scroll-down": ["scrollDown", "Scroll down"]
      };
      const run = {};
      for (const key in triggers) {
        if (typeof m[key] !== "string")
          continue;
        const [trigger, label] = triggers[key];
        def.actions.items.push({
          "id": trigger,
          "name": label,
          "kind": "command",
          "command": m[key],
          "wait": false
        });
        run[trigger] = trigger;
      }
      if (def.actions.items.length > 0)
        def.bar = {
          "run": run
        };
      return def;
    });
  }

  // Ready-made definitions for well-known scripts and commands (partial,
  // no ids). Names: I18n.tr("Notifications (SwayNC)") I18n.tr("Do not disturb (dunst)")
  // I18n.tr("Media (Waybar's mediaplayer.py)") I18n.tr("Package updates")
  // I18n.tr("Weather (wttr.in)") I18n.tr("Failed services") I18n.tr("WireGuard VPN")
  // I18n.tr("GPU load (NVIDIA)") I18n.tr("Daily habits")
  // Their actions' names: I18n.tr("Click") I18n.tr("Right click") I18n.tr("Scroll up")
  // I18n.tr("Scroll down") I18n.tr("Check off") I18n.tr("Add") I18n.tr("Undo")
  // I18n.tr("Remove") I18n.tr("Open") I18n.tr("Set") I18n.tr("Turn on") I18n.tr("Turn off")
  // I18n.tr("Previous") I18n.tr("Play or pause") I18n.tr("Next")
  // Descriptions: I18n.tr("Habits to check off each day, with streaks")
  // Daily habits' texts, which CustomWidgetsEditor.add translates (the
  // typed texts, labels and screen names): I18n.tr("Habits")
  // I18n.tr("All done today") I18n.tr("Add your first habit below")
  // I18n.tr("New habit") I18n.tr("Open") I18n.tr("Done") I18n.tr("Empty")
  readonly property var presets: [
    {
      "name": "Notifications (SwayNC)",
      "icon": "notifications",
      "command": "swaync-client -swb",
      "execIf": "command -v swaync-client",
      "mode": "stream",
      "formatIcons": {
        "notification": "notifications_active",
        "none": "notifications",
        "dnd-notification": "notifications_paused",
        "dnd-none": "notifications_off",
        "inhibited-notification": "notifications_active",
        "inhibited-none": "notifications",
        "dnd-inhibited-notification": "notifications_paused",
        "dnd-inhibited-none": "notifications_off"
      },
      "bar": {
        "style": "icon",
        "run": {
          "click": "click",
          "rightClick": "rightClick"
        }
      },
      "actions": {
        "items": [
          {
            "id": "click",
            "name": "Click",
            "command": "swaync-client -t -sw",
            "wait": false
          },
          {
            "id": "rightClick",
            "name": "Right click",
            "command": "swaync-client -d -sw",
            "wait": false
          }
        ]
      }
    },
    {
      "name": "Do not disturb (dunst)",
      "icon": "notifications",
      "command": "dunstctl is-paused",
      "execIf": "command -v dunstctl",
      "mode": "poll",
      "interval": 2000,
      "output": "text",
      "formatIcons": {
        "true": "notifications_off",
        "false": "notifications"
      },
      "hideEmpty": false,
      "bar": {
        "style": "icon",
        "run": {
          "click": "click"
        }
      },
      "actions": {
        "items": [
          {
            "id": "click",
            "name": "Click",
            "command": "dunstctl set-paused toggle",
            "wait": false
          }
        ]
      }
    },
    {
      "name": "Media (Waybar's mediaplayer.py)",
      "icon": "music_note",
      "command": "~/.config/waybar/mediaplayer.py 2> /dev/null",
      "mode": "stream",
      "formatIcons": {
        "spotify": "music_note",
        "default": "play_circle"
      },
      "maxLength": 40,
      "escape": true,
      "bar": {
        "run": {
          "click": "click",
          "scrollUp": "scrollUp",
          "scrollDown": "scrollDown"
        }
      },
      "actions": {
        "items": [
          {
            "id": "click",
            "name": "Click",
            "command": "playerctl play-pause",
            "wait": false
          },
          {
            "id": "scrollUp",
            "name": "Scroll up",
            "command": "playerctl next",
            "wait": false
          },
          {
            "id": "scrollDown",
            "name": "Scroll down",
            "command": "playerctl previous",
            "wait": false
          }
        ]
      }
    },
    {
      "name": "Package updates",
      "icon": "system_update",
      "command": "checkupdates 2>/dev/null | wc -l | grep -v '^0$'",
      "execIf": "command -v checkupdates",
      "mode": "poll",
      "interval": 1800000,
      "output": "text"
    },
    {
      "name": "Weather (wttr.in)",
      "icon": "partly_cloudy_day",
      "command": "curl -sf 'https://wttr.in/?format=%t+%C'",
      "mode": "poll",
      "interval": 1800000,
      "output": "text"
    },
    {
      "name": "Failed services",
      "icon": "error",
      "command": "systemctl --failed --plain --no-legend | wc -l | grep -v '^0$'",
      "mode": "poll",
      "interval": 60000,
      "output": "text"
    },
    {
      "name": "WireGuard VPN",
      "icon": "vpn_lock",
      "command": "nmcli -t -f TYPE connection show --active | grep -q '^wireguard' && echo on || echo off",
      "execIf": "command -v nmcli",
      "mode": "poll",
      "interval": 5000,
      "output": "text",
      "formatIcons": {
        "on": "vpn_lock",
        "off": "vpn_key_off"
      },
      "bar": {
        "style": "icon"
      }
    },
    {
      "name": "GPU load (NVIDIA)",
      "icon": "memory",
      "command": "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits",
      "execIf": "command -v nvidia-smi",
      "mode": "poll",
      "interval": 3000,
      "output": "text",
      "format": "{}%",
      "bar": {
        "style": "ring"
      }
    },
    {
      "name": "Daily habits",
      "description": "Habits to check off each day, with streaks",
      "template": true,
      "icon": "task_alt",
      "command": "bash '{tree}data/custom-widgets/habits.sh' show",
      "mode": "poll",
      "interval": 60000,
      "output": "json",
      "actions": {
        "items": [
          {
            "id": "check",
            "name": "Check off",
            "kind": "command",
            "command": "bash '{tree}data/custom-widgets/habits.sh' do check {value}",
            "wait": true
          },
          {
            "id": "add",
            "name": "Add",
            "kind": "command",
            "command": "bash '{tree}data/custom-widgets/habits.sh' do add {value}",
            "wait": true
          },
          {
            "id": "undo",
            "name": "Undo",
            "kind": "command",
            "command": "bash '{tree}data/custom-widgets/habits.sh' do undo",
            "wait": true
          },
          {
            "id": "remove",
            "name": "Remove",
            "kind": "command",
            "command": "bash '{tree}data/custom-widgets/habits.sh' do remove {value}",
            "wait": true
          }
        ]
      },
      "format": "{text}",
      "bar": {
        "style": "label",
        "popout": true
      },
      "module": {
        "size": [4, 4],
        "elements": [
          {
            "id": "title",
            "type": "Text",
            "place": {
              "x": 0,
              "y": 0,
              "w": 10,
              "h": 2
            },
            "bind": {
              "text": "Habits"
            },
            "options": {
              "align": "left",
              "bold": true,
              "size": "large"
            }
          },
          {
            "id": "count",
            "type": "Text",
            "place": {
              "x": 10,
              "y": 0,
              "w": 3,
              "h": 2
            },
            "bind": {
              "text": "{text}"
            },
            "options": {
              "align": "right",
              "size": "large",
              "colorStates": root._stateRules("state", [["done", "success"], ["open", "accent"]])
            }
          },
          {
            "id": "undo",
            "type": "Button",
            "place": {
              "x": 13,
              "y": 0,
              "w": 3,
              "h": 2
            },
            "run": {
              "click": "undo"
            },
            "bind": {
              "icon": "undo"
            },
            "options": {
              "disabled": "hide"
            }
          },
          {
            "id": "new",
            "type": "Entry",
            "place": {
              "x": 0,
              "y": 14,
              "w": 16,
              "h": 2
            },
            "run": {
              "submit": "add"
            },
            "bind": {
              "placeholder": "New habit"
            }
          }
        ],
        "views": [
          {
            "id": "open",
            "name": "Open",
            "when": {
              "key": "state",
              "test": "is",
              "values": ["open"]
            },
            "elements": [
              {
                "id": "habits",
                "type": "List",
                "place": {
                  "x": 0,
                  "y": 2,
                  "w": 16,
                  "h": 12
                },
                "run": {
                  "click": "check"
                },
                "options": {
                  "colorStates": root._stateRules("state", [["done", "success"], ["open", "accent"]])
                }
              }
            ]
          },
          {
            "id": "done",
            "name": "Done",
            "when": {
              "key": "state",
              "test": "is",
              "values": ["done"]
            },
            "elements": [
              {
                "id": "mark",
                "type": "Icon",
                "place": {
                  "x": 5,
                  "y": 3,
                  "w": 6,
                  "h": 6
                },
                "bind": {
                  "icon": "task_alt"
                },
                "options": {
                  "color": "success"
                }
              },
              {
                "id": "message",
                "type": "Text",
                "place": {
                  "x": 0,
                  "y": 10,
                  "w": 16,
                  "h": 2
                },
                "bind": {
                  "text": "All done today"
                },
                "options": {
                  "size": "normal"
                }
              }
            ]
          },
          {
            "id": "empty",
            "name": "Empty",
            "when": {
              "key": "state",
              "test": "is",
              "values": ["empty"]
            },
            "elements": [
              {
                "id": "hint",
                "type": "Text",
                "place": {
                  "x": 0,
                  "y": 5,
                  "w": 16,
                  "h": 2
                },
                "bind": {
                  "text": "Add your first habit below"
                },
                "options": {
                  "size": "normal"
                }
              }
            ]
          }
        ]
      },
      "samples": {
        "open": {
          "state": "open",
          "text": "1/3",
          "value": 1,
          "min": 0,
          "max": 3,
          "items": [
            {
              "id": "1",
              "text": "Read",
              "icon": "check_circle",
              "subtext": "4 days",
              "state": "done"
            },
            {
              "id": "2",
              "text": "Walk",
              "icon": "radio_button_unchecked",
              "subtext": "0 days",
              "state": "open"
            },
            {
              "id": "3",
              "text": "Stretch",
              "icon": "radio_button_unchecked",
              "subtext": "2 days",
              "state": "open"
            }
          ],
          "actions": {
            "add": {},
            "check": {},
            "undo": {}
          }
        },
        "done": {
          "state": "done",
          "text": "3/3",
          "value": 3,
          "min": 0,
          "max": 3,
          "items": [
            {
              "id": "1",
              "text": "Read",
              "icon": "check_circle",
              "subtext": "5 days",
              "state": "done"
            },
            {
              "id": "2",
              "text": "Walk",
              "icon": "check_circle",
              "subtext": "1 day",
              "state": "done"
            },
            {
              "id": "3",
              "text": "Stretch",
              "icon": "check_circle",
              "subtext": "3 days",
              "state": "done"
            }
          ],
          "actions": {
            "add": {},
            "check": {},
            "undo": {}
          }
        },
        "empty": {
          "state": "empty",
          "text": "0/0",
          "value": 0,
          "min": 0,
          "max": 0,
          "items": [],
          "actions": {
            "add": {}
          }
        }
      }
    },
    // The gallery's templates: no command, a sample per screen (their texts
    // are English here and translated by CustomWidgetsEditor.add: the
    // names and descriptions, listed here, the `=` literals as the
    // others'): I18n.tr("Toggle") I18n.tr("An on / off switch, such as a VPN")
    // I18n.tr("Slider") I18n.tr("A value you can drag, such as the brightness")
    // I18n.tr("List with a row action") I18n.tr("Rows you can press, such as disks")
    // I18n.tr("Media card") I18n.tr("Playing, paused and nothing playing, with buttons")
    // I18n.tr("Status with an error screen") I18n.tr("A status line, and a screen for when the script fails")
    // I18n.tr("Enabled") I18n.tr("Disks") I18n.tr("Nothing playing") I18n.tr("Restart")
    // I18n.tr("On") I18n.tr("Off") I18n.tr("Playing") I18n.tr("Paused") I18n.tr("Nothing") I18n.tr("Error")
    {
      "name": "Toggle",
      "template": true,
      "description": "An on / off switch, such as a VPN",
      "icon": "toggle_on",
      "actions": {
        "items": [root._act("on", "Turn on"), root._act("off", "Turn off")]
      },
      "module": {
        "size": [4, 2],
        "elements": [root._el("title", "Text", [0, 0, 11, 3], {
            "text": "{text}"
          }, {
            "align": "left",
            "bold": true,
            "size": "large"
          }), root._el("switch", "Toggle", [0, 4, 16, 4], {
            "state": "{state}",
            "label": "Enabled"
          }, null, {
            "on": "on",
            "off": "off"
          })],
        "views": [root._view("on", "On", {
            "key": "state",
            "test": "is",
            "values": ["on"]
          }, [root._el("mark", "Icon", [12, 0, 4, 3], {
              "icon": "lock"
            }, {
              "color": "success"
            })]), root._view("off", "Off", {
            "key": "state",
            "test": "is",
            "values": ["off"]
          }, [root._el("mark", "Icon", [12, 0, 4, 3], {
              "icon": "lock_open"
            }, {
              "color": "warning"
            })])]
      },
      "samples": {
        "on": {
          "state": "on",
          "text": "VPN",
          "actions": {
            "on": {},
            "off": {}
          }
        },
        "off": {
          "state": "off",
          "text": "VPN",
          "actions": {
            "on": {},
            "off": {}
          }
        }
      }
    },
    {
      "name": "Slider",
      "template": true,
      "description": "A value you can drag, such as the brightness",
      "icon": "linear_scale",
      "actions": {
        "items": [root._act("set", "Set")]
      },
      "module": {
        "size": [4, 2],
        "elements": [root._el("title", "Text", [0, 0, 11, 3], {
            "text": "{text}"
          }, {
            "align": "left",
            "bold": true,
            "size": "large"
          }), root._el("amount", "Text", [11, 0, 5, 3], {
            "text": "{value}{unit}"
          }, {
            "align": "right",
            "size": "large"
          }), root._el("slider", "Bar", [0, 4, 16, 3], null, null, {
            "change": "set"
          })]
      },
      "samples": {
        "": {
          "text": "Brightness",
          "value": 60,
          "min": 0,
          "max": 100,
          "unit": "%",
          "actions": {
            "set": {}
          }
        }
      }
    },
    {
      "name": "List with a row action",
      "template": true,
      "description": "Rows you can press, such as disks",
      "icon": "list",
      "actions": {
        "items": [root._act("open", "Open")]
      },
      "module": {
        "size": [4, 4],
        "elements": [root._el("title", "Text", [0, 0, 16, 2], {
            "text": "Disks"
          }, {
            "align": "left",
            "bold": true,
            "size": "large"
          }), root._el("rows", "List", [0, 2, 16, 14], null, {
            "colorStates": root._stateRules("state", [["full", "error"], ["ok", "success"]])
          }, {
            "click": "open"
          })]
      },
      "samples": {
        "": {
          "text": "3 disks",
          "items": [
            {
              "id": "/",
              "text": "/",
              "subtext": "120 GB free",
              "value": 62,
              "max": 100,
              "state": "ok"
            },
            {
              "id": "/home",
              "text": "/home",
              "subtext": "12 GB free",
              "value": 94,
              "max": 100,
              "state": "full"
            },
            {
              "id": "/mnt/data",
              "text": "/mnt/data",
              "subtext": "1.4 TB free",
              "value": 30,
              "max": 100,
              "state": "ok"
            }
          ],
          "actions": {
            "open": {}
          }
        }
      }
    },
    {
      "name": "Media card",
      "template": true,
      "description": "Playing, paused and nothing playing, with buttons",
      "icon": "music_note",
      "actions": {
        "items": [root._act("prev", "Previous"), root._act("toggle", "Play or pause"), root._act("next", "Next")]
      },
      "module": {
        "size": [4, 3],
        "elements": [root._el("title", "Text", [0, 0, 12, 3], {
            "text": "{text}"
          }, {
            "align": "left",
            "bold": true,
            "size": "large"
          }), root._el("artist", "Text", [0, 3, 16, 2], {
            "text": "{subtext}"
          }, {
            "align": "left",
            "size": "normal"
          }), root._el("prev", "Button", [0, 8, 4, 3], {
            "icon": "skip_previous"
          }, null, {
            "click": "prev"
          }), root._el("toggle", "Button", [6, 8, 4, 3], {
            "icon": "{icon}"
          }, null, {
            "click": "toggle"
          }), root._el("next", "Button", [12, 8, 4, 3], {
            "icon": "skip_next"
          }, null, {
            "click": "next"
          })],
        "views": [root._view("playing", "Playing", {
            "key": "state",
            "test": "is",
            "values": ["playing"]
          }, [root._el("mark", "Icon", [12, 0, 4, 3], {
              "icon": "graphic_eq"
            }, {
              "color": "success"
            })]), root._view("paused", "Paused", {
            "key": "state",
            "test": "is",
            "values": ["paused"]
          }, [root._el("mark", "Icon", [12, 0, 4, 3], {
              "icon": "pause_circle"
            }, {
              "color": "warning"
            })]), root._view("nothing", "Nothing", {
            "key": "state",
            "test": "isNot",
            "values": ["playing", "paused"]
          }, [root._el("mark", "Icon", [5, 1, 6, 6], {
              "icon": "music_off"
            }), root._el("message", "Text", [0, 8, 16, 3], {
              "text": "Nothing playing"
            }, {
              "size": "normal"
            })], false)]
      },
      "samples": {
        "playing": {
          "state": "playing",
          "text": "Song title",
          "subtext": "Artist",
          "icon": "pause",
          "actions": {
            "prev": {},
            "toggle": {},
            "next": {}
          }
        },
        "paused": {
          "state": "paused",
          "text": "Song title",
          "subtext": "Artist",
          "icon": "play_arrow",
          "actions": {
            "prev": {},
            "toggle": {},
            "next": {}
          }
        },
        "nothing": {
          "state": "stopped",
          "actions": {}
        }
      }
    },
    {
      "name": "Status with an error screen",
      "template": true,
      "description": "A status line, and a screen for when the script fails",
      "icon": "radio_button_checked",
      "actions": {
        "items": [
          {
            "id": "restart",
            "name": "Restart",
            "kind": "axiom",
            "axiom": "restart"
          }
        ]
      },
      "module": {
        "size": [4, 2],
        "elements": [root._el("status", "Status", [0, 0, 10, 3], {
            "text": "{text}"
          }), root._el("detail", "Text", [0, 3, 16, 3], {
            "text": "{subtext}"
          }, {
            "align": "left",
            "size": "normal"
          })],
        "views": [root._view("error", "Error", {
            "key": "error",
            "test": "set",
            "values": []
          }, [root._el("mark", "Icon", [0, 0, 4, 4], {
              "icon": "error"
            }), root._el("message", "Text", [4, 0, 12, 4], {
              "text": "{error}"
            }, {
              "align": "left",
              "size": "normal"
            }), root._el("retry", "Button", [4, 5, 8, 3], null, null, {
              "click": "restart"
            })], false)]
      },
      "samples": {
        "": {
          "state": "ok",
          "text": "All good",
          "subtext": "Checked just now"
        },
        "error": {
          "error": "Could not reach the server"
        }
      }
    }
  ]

  // The module lattice: the elements' bounds (the editor keeps them from
  // the top left, so the box fits them), or for none a design size [w, h]
  // in grid units. { cols, rows } in sub-cells
  function lattice(elements, size) {
    const els = elements ?? [];
    if (els.length)
      return {
        "cols": Math.max(1, ...els.map(e => (e.place?.x ?? 0) + (e.place?.w ?? 1))),
        "rows": Math.max(1, ...els.map(e => (e.place?.y ?? 0) + (e.place?.h ?? 1)))
      };
    return {
      "cols": Math.max(1, (size?.[0] ?? 4) * root.subCells),
      "rows": Math.max(1, (size?.[1] ?? 2) * root.subCells)
    };
  }

  // The module's size [w, h] in grid units, as fractions (the popout's)
  function designSize(elements, size) {
    const g = root.lattice(elements, size);
    return [g.cols / root.subCells, g.rows / root.subCells];
  }

  // The whole grid units a page starts the module at: designSize rounded up
  function pageSize(elements, size) {
    return root.designSize(elements, size).map(n => Math.max(1, Math.ceil(n)));
  }

  // Where content `free` px short of its box starts along an axis: 0 for
  // left | top (and anything unknown), half for center | middle, all of it for
  // right | bottom. An element's `align` (across) and `valign` (down)
  function alignOffset(align, free) {
    const room = Math.max(0, free);
    return align === "center" || align === "middle" ? room / 2 : align === "right" || align === "bottom" ? room : 0;
  }

  // How many lines of text `size` px tall a box `height` px tall holds (at
  // least 1): a Text's `maxLines`, so a size too big for its box elides on
  // its first line instead of being cut through
  function textLines(height, size) {
    return Math.max(1, Math.floor(height / Math.max(1, size * 1.3)));
  }

  // An element's rect in px: `place` { x, y, w, h } in sub-cells on a
  // lattice of { cols, rows }, laid over `width` × `height` with `gap`
  // between neighbours (proportional: any size works). Empty without a
  // place (an element slot before its element arrives)
  function rect(place, grid, width, height, gap) {
    if (!place)
      return {
        "x": 0,
        "y": 0,
        "width": 0,
        "height": 0
      };
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

  // The elements drawn for a definition without any (a module never shows
  // empty): an icon (a ring when there's a value) and the text beside it,
  // filling a lattice of `size`, the text against the icon as a built-in
  // figure sits
  function defaultElements(size, hasValue) {
    const g = root.lattice([], size);
    const side = Math.max(1, Math.min(g.rows, Math.floor(g.cols / 3)));
    const out = [
      {
        "id": "icon",
        "type": hasValue ? "Ring" : "Icon",
        "place": {
          "x": 0,
          "y": 0,
          "w": side,
          "h": g.rows
        },
        "bind": hasValue ? {
          "value": "{value}"
        } : {},
        "options": {}
      }
    ];
    if (g.cols - side > 0)
      out.push({
        "id": "text",
        "type": "Text",
        "place": {
          "x": side,
          "y": 0,
          "w": g.cols - side,
          "h": g.rows
        },
        "bind": {
          "text": "{text}"
        },
        "options": {
          "align": "left",
          "size": "large"
        }
      });
    return out;
  }

  // The zoom (at most 0.3, at least 0.05) the Module tab's size previews
  // are drawn at: the one that fits its height (their tallest, at least four
  // units, a fifth of the height) and its width. `sizes` are the previews'
  // [w, h] in grid units, `card` the card size, `reserved` the px beside
  // them and `spacing` the px between them.
  function previewZoom(sizes, card, width, height, reserved, spacing) {
    const tall = Math.max(4, ...sizes.map(size => size[1]));
    const byHeight = height * 0.22 / Math.max(1, GridPlacement.span(tall, card));
    const across = sizes.reduce((sum, size) => sum + GridPlacement.span(size[0], card), 0);
    const byWidth = (width - reserved - spacing * sizes.length) / Math.max(1, across);
    return Math.max(0.05, Math.min(0.3, byHeight, byWidth));
  }

  // The zoom (at most 1, at least 0.05) a module of `size` ([w, h] in grid
  // units, `card` px a unit) is drawn at to fit `width` by `height`: the
  // test preview, one large preview
  function fitZoom(size, card, width, height) {
    const w = Math.max(1, GridPlacement.span(size[0], card));
    const h = Math.max(1, GridPlacement.span(size[1], card));
    return Math.max(0.05, Math.min(1, width / w, height / h));
  }

  // --- Screens (module.views) ---

  // The module's elements in every layer: the base, then each screen's
  // (the lattice and the design size cover all of them)
  function allElements(module) {
    let out = (module?.elements ?? []).slice();
    for (const view of module?.views ?? [])
      out = out.concat(view.elements ?? []);
    return out;
  }

  // Whether a screen's `when` ({ key, test (is, isNot, set, unset),
  // values }) holds for the resolved `fields` (null: never). The key
  // "error" is the failure: set while there is one, `is` / `isNot`
  // compare its message, and never hold while it isn't failing; any other is a key or path in the sample.
  // An empty key never holds (only a Go to screen action shows that screen)
  function matches(when, fields) {
    if (!fields || !(when?.key ?? ""))
      return false;
    const test = when?.test ?? "is";
    const values = when?.values ?? [];
    if (when.key === "error") {
      if (test === "set")
        return fields.failure !== null && fields.failure !== undefined;
      if (test === "unset")
        return fields.failure === null || fields.failure === undefined;
      if (fields.failure === null || fields.failure === undefined)
        return false;
      const message = fields.error ?? "";
      return test === "isNot" ? values.length > 0 && !values.includes(message) : values.includes(message);
    }
    const v = root.get(fields.sample, when.key);
    if (test === "set")
      return root.truthy(v);
    if (test === "unset")
      return !root.truthy(v);
    const text = root.asText(v);
    return test === "isNot" ? values.length > 0 && !values.includes(text) : values.includes(text);
  }

  // The first screen whose condition holds (a non-empty key that
  // matches), else -1
  function conditionView(module, fields) {
    return (module?.views ?? []).findIndex(v => !!(v.when?.key ?? "") && root.matches(v.when, fields));
  }

  // The screen to draw: { index (-1: the base alone), builtinError (the
  // failure has no screen of its own: draw the stock one) }. `chosen` is
  // a Go to screen choice, { view: "<id>" | "" (the base), matched: the
  // conditionView when it was made } or null: it wins until the condition
  // picks another screen, and an id that no longer exists is ignored.
  // While the widget fails only screens keyed on "error" are tried
  function pickView(module, fields, chosen) {
    const views = module?.views ?? [];
    if (fields?.failure) {
      const index = views.findIndex(v => v.when?.key === "error" && root.matches(v.when, fields));
      return {
        "index": index,
        "builtinError": index < 0
      };
    }
    const c = root.conditionView(module, fields);
    let index = c;
    if (chosen && chosen.matched === c) {
      const own = chosen.view === "" ? -1 : views.findIndex(v => v.id === chosen.view);
      if (own >= 0 || chosen.view === "")
        index = own;
    }
    return {
      "index": index,
      "builtinError": false
    };
  }

  // A series a script prints: `v` (a list) as its finite numbers (a
  // numeric string is parsed, anything else dropped), the last `cap`; null
  // when `v` isn't a list
  function series(v, cap) {
    if (!Array.isArray(v))
      return null;
    const out = [];
    for (const item of v) {
      const n = root._number(item);
      if (n !== undefined)
        out.push(n);
    }
    return cap > 0 ? out.slice(-cap) : out;
  }

  // The distinct `value` and `value2` bindings of every Sparkline in every
  // layer: what the service keeps a history of (a binding whose value is a
  // list needs none: it is the series)
  function historyBindings(module) {
    const out = [];
    for (const e of root.allElements(module)) {
      if (e.type !== "Sparkline")
        continue;
      for (const b of [e.bind?.value, e.bind?.value2]) {
        if (b && out.indexOf(b) < 0)
          out.push(b);
      }
    }
    return out;
  }

  // --- Named actions ---

  // The action of `def` (`actions.items`) that `ref` names: by id, else by
  // name (the IPC takes either); null for "" or none
  function actionOf(def, ref) {
    const key = String(ref ?? "");
    if (key === "")
      return null;
    const items = def?.actions?.items ?? [];
    return items.find(a => a.id === key) ?? items.find(a => a.name === key) ?? null;
  }

  // The values an Axiom action can take, in order: refresh, restart, screen:
  // (the base), screen:<id> for each of `screenIds`, then each of `shellIds`
  // (the caller sorts them by label) that isn't in `refused` and takes no
  // argument (`needsArgument`: an id → bool, or a list of ids)
  function axiomValues(shellIds, refused, needsArgument, screenIds) {
    const takes = id => typeof needsArgument === "function" ? !!needsArgument(id) : (needsArgument ?? []).indexOf(id) >= 0;
    const out = ["refresh", "restart", "screen:"];
    for (const id of screenIds ?? [])
      out.push("screen:" + id);
    for (const id of shellIds ?? []) {
      if (root.builtinAllowed(id, refused) && !takes(id) && out.indexOf(id) < 0)
        out.push(id);
    }
    return out;
  }

  // The `run` objects of a definition's elements (every layer) and of its bar
  function _runs(def) {
    const out = root.allElements(def?.module).map(e => e.run);
    out.push(def?.bar?.run);
    return out.filter(r => r !== null && r !== undefined && typeof r === "object");
  }

  // How many triggers (elements' `run`, the bar's `bar.run`) name action `id`
  function actionRefs(def, id) {
    let n = 0;
    for (const run of root._runs(def)) {
      for (const trigger of Object.keys(run)) {
        if (run[trigger] === id)
          n++;
      }
    }
    return n;
  }

  // `def` as a copy whose triggers that name action `id` name none
  function withoutActionRefs(def, id) {
    const copy = Utils.clone(def);
    for (const run of root._runs(copy)) {
      for (const trigger of Object.keys(run)) {
        if (run[trigger] === id)
          run[trigger] = "";
      }
    }
    return copy;
  }

  // Whether the sample lets action `item` (an entry of `actions.items`)
  // run: an Axiom one always, everything when the sample lists no actions
  // (null), else only the ids it lists as enabled
  function actionEnabled(actions, item) {
    if (item?.kind === "axiom" || actions === null || actions === undefined)
      return true;
    const id = item?.id ?? "";
    return Object.prototype.hasOwnProperty.call(actions, id) && actions[id]?.enabled === true;
  }

  // `text` as one shell word: a plain number as is, anything else in
  // single quotes (a ' as '\''), nothing as ''
  function shellQuote(text) {
    const t = String(text ?? "");
    return /^-?(\d+(\.\d+)?|\.\d+)$/.test(t) ? t : "'" + t.replace(/'/g, "'\\''") + "'";
  }

  // An action command with its placeholders filled in one pass: {value}
  // and {rev} already quoted (shellQuote), {tree} as is. `values`
  // holds the ones to fill; a placeholder it has no value for, one after
  // a $ (${rev}) and any other {…} stay as typed. A filled value is never
  // searched again
  function fillCommand(template, values) {
    return String(template ?? "").replace(/\$?\{(value|rev|tree)\}/g, (m, k) => m[0] === "$" || !(k in values) ? m : k === "tree" ? values.tree : root.shellQuote(root.asText(values[k])));
  }

  // Whether a shell action (a bare id: "lock", "overlay") may run from a
  // widget: not one of `refused` (the session's and the destructive ones,
  // which a stray press or script must never run)
  function builtinAllowed(id, refused) {
    return !(refused ?? []).includes(String(id));
  }

  // --- Samples ---

  // The UTF-8 byte length of `text` (a lone surrogate counts as 3, as it
  // would be written as U+FFFD)
  function utf8Length(text) {
    const t = String(text ?? "");
    let n = 0;
    for (let i = 0; i < t.length; i++) {
      const c = t.charCodeAt(i);
      if (c < 0x80) {
        n += 1;
      } else if (c < 0x800) {
        n += 2;
      } else if (c >= 0xD800 && c < 0xDC00 && i + 1 < t.length && t.charCodeAt(i + 1) >= 0xDC00 && t.charCodeAt(i + 1) < 0xE000) {
        n += 4;
        i++;
      } else {
        n += 3;
      }
    }
    return n;
  }

  // The key a screen's sample is kept under: its id, "" for no screen
  // (the base alone)
  function viewKey(module, index) {
    return index < 0 || !module?.views?.[index] ? "" : module.views[index].id;
  }

  // `sample` kept under `key` in `samples` (a screen id, "" for none):
  // { samples (a new map; the old one when refused), refused ("count": a
  // new key past limits.entries, "size": the whole past limits.bytes
  // as JSON, else "") }. Nothing passed in is changed
  function keepSample(samples, key, sample, limits) {
    const old = samples ?? {};
    const next = Object.assign({}, old);
    next[key] = sample;
    const lim = limits ?? {};
    let refused = "";
    if (!(key in old) && Object.keys(next).length > (lim.entries ?? Infinity))
      refused = "count";
    else if (root.utf8Length(JSON.stringify(next)) > (lim.bytes ?? Infinity))
      refused = "size";
    return {
      "samples": refused === "" ? next : Object.assign({}, old),
      "refused": refused
    };
  }

  // The sample the editor previews screen `index` (-1: no screen) with: the
  // one kept in the definition, else the last one seen live for it (`seen`:
  // key -> sample), else the live one when it is what picks that screen
  // (`liveFields`, resolved: pickView), else null
  function sampleForView(definition, index, seen, liveFields) {
    const key = root.viewKey(definition?.module, index);
    const kept = definition?.samples?.[key];
    if (kept !== undefined && kept !== null)
      return kept;
    const last = seen?.[key];
    if (last !== undefined && last !== null)
      return last;
    return liveFields && root.pickView(definition?.module, liveFields).index === index ? liveFields.sample : null;
  }

  // --- The editor's pure parts (docs/dev/features/custom-widgets.md › The page) ---

  // `list` with the item at `from` moved to `to` (a new list; the same
  // when either is out of range or they are equal)
  function moveItem(list, from, to) {
    const items = list ?? [];
    if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length)
      return items;
    const next = items.slice();
    next.splice(to, 0, next.splice(from, 1)[0]);
    return next;
  }

  // A copy of screen `index` of `views` for the editor's Duplicate: a new id
  // and `name`, its elements and condition copied (its sample is not: that
  // is kept under the screen's id). Null for none
  function viewCopy(views, index, name) {
    const source = views?.[index];
    if (!source)
      return null;
    const copy = Utils.clone(source);
    copy.id = Utils.newId(Utils.slug(name) || source.id, views);
    copy.name = name;
    return copy;
  }

  // `element` as it lands in another layer (`elements`): its place kept, a
  // new id when `elements` has it already
  function elementCopy(elements, element) {
    const copy = Utils.clone(element);
    if ((elements ?? []).some(e => e.id === copy.id))
      copy.id = Utils.newId(copy.id, elements);
    return copy;
  }

  // The paths the editor offers to bind from, over `samples` (an output
  // each, null ones skipped), first seen first, each path once, leaves and
  // lists only: [{ path, type, value (the list's length), preview (a leaf's
  // text, at most 40 characters) }]
  function bindChoices(samples, cap) {
    const out = [];
    const seen = new Set();
    for (const sample of samples ?? []) {
      if (sample === null || sample === undefined || typeof sample !== "object")
        continue;
      for (const p of root.flatten(sample)) {
        if (p.type === "object" || seen.has(p.path))
          continue;
        seen.add(p.path);
        const text = p.type === "array" ? "" : root.asText(p.value);
        out.push({
          "path": p.path,
          "type": p.type,
          "value": p.value,
          "preview": text.length > 40 ? text.slice(0, 39) + "…" : text
        });
        if (out.length >= (cap ?? 200))
          return out;
      }
    }
    return out;
  }

  // Every command a definition holds, what Import lists before anything
  // runs and Copy warns about: [{ where, command }], the non-empty ones of
  // `command`, `execIf` and each command action ("actions/<name or id>")
  function commandsOf(definition) {
    const out = [];
    const add = (where, command) => {
      if (typeof command === "string" && command.trim() !== "")
        out.push({
          "where": where,
          "command": command
        });
    };
    const def = definition ?? {};
    add("command", def.command);
    add("execIf", def.execIf);
    for (const item of def.actions?.items ?? []) {
      if (item.kind !== "axiom")
        add("actions/" + (item.name || item.id), item.command);
    }
    return out;
  }

  // The text Copy puts on the clipboard: T30's wrapper around `definition`
  // without its id (the new owner's list gives it one), as JSON
  function exportOf(definition) {
    const copy = Utils.clone(definition);
    delete copy.id;
    return JSON.stringify({
      "axiomCustomWidget": 1,
      "definition": copy
    }, null, 2);
  }

  // Pasted text read as shared widgets: { definitions (partial, ids
  // dropped), error, detail }. `error` is a code, "" when good: "json"
  // (`detail` says why), "notWidget" (an item that is no object), "newer",
  // "noModule" (no module and no command) or "empty". The wrapper Copy
  // makes, a bare definition, or a list of either; comments and trailing
  // commas are allowed
  function fromExport(text) {
    let parsed;
    try {
      parsed = JSON.parse(root.stripJsonc(text).trim());
    } catch (e) {
      return {
        "definitions": [],
        "error": "json",
        "detail": e.message
      };
    }
    const definitions = [];
    for (const item of Array.isArray(parsed) ? parsed : [parsed]) {
      if (item === null || typeof item !== "object" || Array.isArray(item))
        return {
          "definitions": [],
          "error": "notWidget",
          "detail": ""
        };
      let def = item;
      if ("axiomCustomWidget" in item) {
        if (typeof item.axiomCustomWidget !== "number" || item.axiomCustomWidget > 1)
          return {
            "definitions": [],
            "error": "newer",
            "detail": ""
          };
        def = item.definition;
      }
      if (def === null || typeof def !== "object" || Array.isArray(def) || (!def.module && !def.command))
        return {
          "definitions": [],
          "error": "noModule",
          "detail": ""
        };
      const copy = Utils.clone(def);
      delete copy.id;
      definitions.push(copy);
    }
    return {
      "definitions": definitions,
      "error": definitions.length ? "" : "empty",
      "detail": ""
    };
  }

  // What the Import form reads from a paste: a shared widget (fromExport)
  // first, else a Waybar `custom/*` module (fromWaybar). { definitions,
  // error ("" when good, "json" with its `detail`, else "neither"), detail,
  // kind ("widget", "waybar", "" when it read neither) }
  function readImport(text) {
    const shared = root.fromExport(text);
    if (shared.error === "")
      return {
        "definitions": shared.definitions,
        "error": "",
        "detail": "",
        "kind": "widget"
      };
    try {
      const waybar = root.fromWaybar(text);
      if (waybar.length)
        return {
          "definitions": waybar,
          "error": "",
          "detail": "",
          "kind": "waybar"
        };
    } catch (e) {
      // Not Waybar's either: the first reading's error says why
    }
    return {
      "definitions": [],
      "error": shared.error === "json" ? "json" : "neither",
      "detail": shared.error === "json" ? shared.detail : "",
      "kind": ""
    };
  }

  // `list` with `entry` added, the last `cap` kept (the editor's action log)
  function pushLog(list, entry, cap) {
    return (list ?? []).concat([entry]).slice(-cap);
  }

  // Where the sample a screen (-1: none) is previewed with comes from, as
  // sampleForView picks it: "saved" (kept in the definition), "live" (the
  // last one seen, or the output now) or "none"
  function sampleSource(definition, index, seen, liveFields) {
    const key = root.viewKey(definition?.module, index);
    const kept = definition?.samples?.[key];
    if (kept !== undefined && kept !== null)
      return "saved";
    return root.sampleForView(definition, index, seen, liveFields) === null ? "none" : "live";
  }

  // What a definition offered on the lock screen holds that doesn't work
  // there or shows a script's text to whoever sees the screen: "actions"
  // (an element or the bar runs an action), "entry" (an
  // Entry element), "text" (an element's `text` bound to the output). []
  // when it holds none
  function lockIssues(definition) {
    const module = definition?.module;
    const elements = root.allElements(module);
    const issues = [];
    if (root._runs(definition).some(run => Object.values(run).some(id => !!id)))
      issues.push("actions");
    if (elements.some(e => e.type === "Entry"))
      issues.push("entry");
    if (elements.some(e => (e.bind?.text ?? "").indexOf("{") >= 0))
      issues.push("text");
    return issues;
  }

  // A template's element ([x, y, w, h] in sub-cells; `run`: its triggers'
  // action ids)
  function _el(id, type, place, bind, options, run) {
    const element = {
      "id": id,
      "type": type,
      "place": {
        "x": place[0],
        "y": place[1],
        "w": place[2],
        "h": place[3]
      }
    };
    if (bind)
      element.bind = bind;
    if (options)
      element.options = options;
    if (run)
      element.run = run;
    return element;
  }

  // A "Color by state" setting reading `key`: one `is` rule per [value, colour]
  function _stateRules(key, pairs) {
    return {
      "enabled": true,
      "key": key,
      "rules": pairs.map(p => ({
            "test": "is",
            "value": p[0],
            "color": p[1]
          }))
    };
  }

  // A template's command action (its command is the script's, set when
  // there is one)
  function _act(id, name) {
    return {
      "id": id,
      "name": name,
      "kind": "command",
      "command": "",
      "wait": true
    };
  }

  // A template's screen
  function _view(id, name, when, elements, base) {
    return {
      "id": id,
      "name": name,
      "base": base !== false,
      "when": when,
      "elements": elements
    };
  }

  // The presets the New chooser's "From a known script" lists (the ones
  // with a command, Daily habits too) and the ones its gallery draws
  // (`template`: a ready look with a sample per screen, drawn before any
  // script exists)
  readonly property var scriptPresets: root.presets.filter(p => !!p.command)
  readonly property var galleryPresets: root.presets.filter(p => p.template)
}
