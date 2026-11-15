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

  // A value as text: "" for nothing, JSON for an object or list
  function asText(v) {
    return v === undefined || v === null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
  }

  // A list of rows (an output's items, or a bound list) as
  // { text, icon, value (a number, or undefined), subtext, id, state (its
  // tone's word), max (a number above 0 that a numeric value is out of, else
  // undefined: the row draws a meter), image (a path or URL) }: a plain
  // entry is its text, the rest empty; anything not a list is none
  function rows(v) {
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
          "image": ""
        };
      const value = root._number(i.value);
      const max = root._number(i.max);
      return {
        "text": root.asText(i.text),
        "icon": root.asText(i.icon),
        "value": value,
        "subtext": root.asText(i.subtext),
        "id": root.asText(i.id),
        "state": root.asText(i.state),
        "max": value !== undefined && max !== undefined && max > 0 ? max : undefined,
        "image": root.asText(i.image)
      };
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
  function fill(template, values) {
    return String(template ?? "").replace(/\{([^{}:]*)(?::[^{}]*)?\}/g, (match, name) => {
      const key = name === "" || name === "0" ? "text" : name;
      return root.asText(key in values ? values[key] : root.get(values._sample, key));
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

  // The theme colour name for a state. The first that holds: `states` (over
  // defaultStates) maps `state`; `state` is itself a theme colour name; the
  // first class `states` maps. "" when none: a state that is neither
  // mapped nor a theme name (a hex too) colours nothing.
  function stateColor(state, classList, states, colorNames) {
    const map = Object.assign({}, root.defaultStates, states ?? {});
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
  //                 states, maxLength, escape, hideEmpty }
  // Returns { text (rich, the format filled), plain (it as plain text),
  // rawText, alt, tooltip (rich), classes, color (a theme colour name,
  // "" for none), percentage, value, min, max (0-100 unless given), hasMax
  // (the output gave a max or a percentage), ratio (0-1, or -1 without a
  // value), state, rev, actions (actionsOf), failure (failure), error (its
  // message), hiddenByScript (the output's own `hidden`), interactive, states (the
  // definition's map) and colorNames (the context's), which `tone` reads,
  // unit, subtext, icon (a Material Symbols name), glyph (the
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
      "color": root.stateColor(str(f.state), classList, d.states, context?.colorNames),
      "state": str(f.state),
      "rev": str(f.rev),
      "actions": root.actionsOf(f.actions),
      "failure": failure,
      "error": failure?.message ?? "",
      "interactive": !!context?.interactive,
      "states": d.states ?? {},
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
  readonly property var _internalFields: ["states", "colorNames", "actions", "interactive", "failure"]

  // An element's own binding: a literal when it starts with "=" (the rest,
  // as text: `=Show answer`, `=task_alt`, `=5`), a format when it has a "{"
  // (filled from the resolved fields, then the sample), else a field name,
  // else a path in the sample. Returns the raw value (a format: its string).
  function elementValue(fields, binding) {
    if (!binding)
      return undefined;
    const b = String(binding);
    if (b[0] === "=")
      return b.slice(1);
    // A number typed as the binding (a max of 100)
    if (/^-?\d+(\.\d+)?$/.test(b.trim()))
      return Number(b);
    if (b.indexOf("{") >= 0) {
      const values = Object.assign({}, fields, {
        "_sample": fields?.sample,
        "text": fields?.plain,
        "icon": fields?.glyph
      });
      for (const key of root._internalFields)
        delete values[key];
      return root.fill(b, values);
    }
    // `sample` and resolve's own bookkeeping aren't fields a script prints
    if (fields && b in fields && b !== "sample" && root._internalFields.indexOf(b) < 0)
      return fields[b];
    return root.get(fields?.sample, b);
  }

  // Whether an element is shown: its `show` binding holds (truthy), or it
  // has none
  function elementShown(fields, bind) {
    return !bind?.show || root.truthy(root.elementValue(fields, bind.show));
  }

  // The theme colour name an element's `tone` binding gives: its value
  // looked up in the definition's states (a theme colour name passes
  // through; a hex or an unknown word is ""), "" without a binding
  function elementTone(fields, bind) {
    return bind?.tone ? root.stateColor(root.asText(root.elementValue(fields, bind.tone)), [], fields?.states, fields?.colorNames) : "";
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
  //   on-click(-right, -middle), on-scroll-up/down; signal → refreshName
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
        "actions": {}
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
      const actions = {
        "on-click": "click",
        "on-click-right": "rightClick",
        "on-click-middle": "middleClick",
        "on-scroll-up": "scrollUp",
        "on-scroll-down": "scrollDown"
      };
      for (const key in actions) {
        if (typeof m[key] === "string")
          def.actions[actions[key]] = m[key];
      }
      return def;
    });
  }

  // Ready-made definitions for well-known scripts and commands (partial,
  // no ids). Names: I18n.tr("Notifications (SwayNC)") I18n.tr("Do not disturb (dunst)")
  // I18n.tr("Media (Waybar's mediaplayer.py)") I18n.tr("Package updates")
  // I18n.tr("Weather (wttr.in)") I18n.tr("Failed services") I18n.tr("WireGuard VPN")
  // I18n.tr("GPU load (NVIDIA)") I18n.tr("Daily habits")
  // Daily habits' texts, which CustomWidgetsEditor.add translates (the
  // `=` literals, options and screen names): I18n.tr("Habits")
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
        "style": "icon"
      },
      "actions": {
        "click": "swaync-client -t -sw",
        "rightClick": "swaync-client -d -sw"
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
        "style": "icon"
      },
      "actions": {
        "click": "dunstctl set-paused toggle"
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
      "actions": {
        "click": "playerctl play-pause",
        "scrollUp": "playerctl next",
        "scrollDown": "playerctl previous"
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
      "icon": "task_alt",
      "command": "bash '{tree}data/custom-widgets/habits.sh' show",
      "mode": "poll",
      "interval": 60000,
      "output": "json",
      "invoke": {
        "command": "bash '{tree}data/custom-widgets/habits.sh' do {action} {value}"
      },
      "format": "{text}",
      "states": {
        "done": "success",
        "open": "accent"
      },
      "bar": {
        "style": "label",
        "popout": true
      },
      "module": {
        "size": [4, 4],
        "keys": {
          "u": "undo"
        },
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
              "text": "=Habits"
            },
            "options": {
              "align": "left",
              "bold": true
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
              "text": "{text}",
              "tone": "state"
            },
            "options": {
              "align": "right"
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
            "action": "undo",
            "options": {
              "icon": "undo",
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
            "action": "add",
            "options": {
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
                "action": "check"
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
                  "icon": "=task_alt",
                  "tone": "state"
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
                  "text": "=All done today"
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
                  "text": "=Add your first habit below"
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
        "bind": {},
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
        "bind": {},
        "options": {
          "align": "left"
        }
      });
    return out;
  }

  // The Module tab's lock-screen column width: its base width, or its widest
  // child's (the "Start from the default layout" button, whose label never
  // wraps or elides) when that is wider
  function lockColumnWidth(base, buttonWidth) {
    return Math.max(base, Math.ceil(buttonWidth));
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
  // compare its message, and never hold while it isn't failing; any other is a key or path in the sample
  // ("state" when empty)
  function matches(when, fields) {
    if (!fields)
      return false;
    const test = when?.test ?? "is";
    const values = when?.values ?? [];
    if ((when?.key ?? "state") === "error") {
      if (test === "set")
        return fields.failure !== null && fields.failure !== undefined;
      if (test === "unset")
        return fields.failure === null || fields.failure === undefined;
      if (fields.failure === null || fields.failure === undefined)
        return false;
      const message = fields.error ?? "";
      return test === "isNot" ? values.length > 0 && !values.includes(message) : values.includes(message);
    }
    const v = root.get(fields.sample, when?.key || "state");
    if (test === "set")
      return root.truthy(v);
    if (test === "unset")
      return !root.truthy(v);
    const text = root.asText(v);
    return test === "isNot" ? values.length > 0 && !values.includes(text) : values.includes(text);
  }

  // The screen to draw: { index (-1: the base alone), builtinError (the
  // failure has no screen of its own: draw the stock one) }. While the
  // widget fails only screens keyed on "error" are tried
  function pickView(module, fields) {
    const views = module?.views ?? [];
    if (fields?.failure) {
      const index = views.findIndex(v => v.when?.key === "error" && root.matches(v.when, fields));
      return {
        "index": index,
        "builtinError": index < 0
      };
    }
    return {
      "index": views.findIndex(v => root.matches(v.when, fields)),
      "builtinError": false
    };
  }

  // Each kind's slot list (`slotLists`, the kinds' x-slots) in the same
  // order, the slots every list has moved to the end, in the first list's
  // order: the base's slots are the ones every kind has; Separator has only
  // those
  function baseSlotsLast(slotLists) {
    const shared = slotLists.length === 0 ? [] : slotLists[0].filter(s => slotLists.every(l => l.indexOf(s) >= 0));
    return slotLists.map(l => l.filter(s => shared.indexOf(s) < 0).concat(shared));
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

  // Whether the sample lets action `id` run: a built-in ("axiom:…") always,
  // everything when the sample lists no actions (null), else only the
  // ids it lists as enabled
  function actionEnabled(actions, id) {
    if (String(id).startsWith("axiom:") || actions === null || actions === undefined)
      return true;
    return Object.prototype.hasOwnProperty.call(actions, id) && actions[id]?.enabled === true;
  }

  // `text` as one shell word: a plain number as is, anything else in
  // single quotes (a ' as '\''), nothing as ''
  function shellQuote(text) {
    const t = String(text ?? "");
    return /^-?(\d+(\.\d+)?|\.\d+)$/.test(t) ? t : "'" + t.replace(/'/g, "'\\''") + "'";
  }

  // An action command with its placeholders filled in one pass: {action},
  // {value} and {rev} already quoted (shellQuote), {tree} as is. `values`
  // holds the ones to fill; a placeholder it has no value for, one after
  // a $ (${rev}) and any other {…} stay as typed. A filled value is never
  // searched again
  function fillCommand(template, values) {
    return String(template ?? "").replace(/\$?\{(action|value|rev|tree)\}/g, (m, k) => m[0] === "$" || !(k in values) ? m : k === "tree" ? values.tree : root.shellQuote(root.asText(values[k])));
  }

  // Whether a built-in action ("axiom:<id>") may run from a widget: not
  // one of `refused` (the session's and the destructive ones, which a
  // stray key press or script must never run)
  function builtinAllowed(id, refused) {
    const text = String(id);
    return !(text.startsWith("axiom:") && (refused ?? []).includes(text.slice(6)));
  }

  // --- Keys ---

  // Keys a module's `keys` never take: Escape closes an edge menu, Tab
  // moves the focus
  readonly property var reservedKeys: ["escape", "tab", "shift+tab"]

  // The name a key press goes by in a module's `keys` ("3", "space",
  // "ctrl+z"), or "" for none: a key held down (auto-repeat) is none, so a
  // held key acts once. A printed key is its text, lower-cased; with Ctrl
  // or Alt its name comes from `key` instead (A to Z, 0 to 9: `text` is
  // then a control character), prefixed "ctrl+" and "alt+". The others are
  // space, return, backspace, left, right, up, down, escape and tab, which
  // add "shift+" when Shift is down. `modifiers` is Qt's bit set
  function keyName(key, text, modifiers, autoRepeat) {
    if (autoRepeat)
      return "";
    const ctrl = (modifiers & Qt.ControlModifier) !== 0;
    const alt = (modifiers & Qt.AltModifier) !== 0;
    const shift = (modifiers & Qt.ShiftModifier) !== 0;
    const named = {};
    named[Qt.Key_Space] = "space";
    named[Qt.Key_Return] = "return";
    named[Qt.Key_Enter] = "return";
    named[Qt.Key_Backspace] = "backspace";
    named[Qt.Key_Left] = "left";
    named[Qt.Key_Right] = "right";
    named[Qt.Key_Up] = "up";
    named[Qt.Key_Down] = "down";
    named[Qt.Key_Escape] = "escape";
    named[Qt.Key_Tab] = "tab";
    named[Qt.Key_Backtab] = "tab";
    let base = named[key] ?? "";
    let printed = false;
    if (base === "") {
      printed = true;
      if (ctrl || alt) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
          base = String.fromCharCode(97 + key - Qt.Key_A);
        else if (key >= Qt.Key_0 && key <= Qt.Key_9)
          base = String.fromCharCode(48 + key - Qt.Key_0);
      } else {
        const t = String(text ?? "");
        const code = t.codePointAt(0) ?? 0;
        if ([...t].length === 1 && code >= 32 && code !== 127)
          base = t.toLowerCase();
      }
    }
    if (base === "")
      return "";
    return (ctrl ? "ctrl+" : "") + (alt ? "alt+" : "") + ((shift || key === Qt.Key_Backtab) && !printed ? "shift+" : "") + base;
  }

  // The action `keys` (a module's key name → action id) gives key `name`,
  // "" for none: a reserved key, one the module doesn't map, and never a
  // name every object has (`constructor`, …)
  function keyAction(keys, name) {
    if (name === "" || root.reservedKeys.includes(name) || keys === null || typeof keys !== "object")
      return "";
    return Object.prototype.hasOwnProperty.call(keys, name) && typeof keys[name] === "string" ? keys[name] : "";
  }

  // Whether `item` is `ancestor` or sits under it (by `parent`): where the
  // window's focus is, relative to a module's layout
  function within(ancestor, item) {
    for (let it = item; it; it = it.parent) {
      if (it === ancestor)
        return true;
    }
    return false;
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
}
