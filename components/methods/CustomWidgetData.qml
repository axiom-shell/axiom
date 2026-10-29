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

  // The fields of one sample as a definition draws them, each read from
  // the key of the same name (a script shapes its own JSON). Plain text
  // that's a number is the value; text matching a format-icons key is the
  // alt (so a script printing "on" picks the "on" icon); a format-icons
  // pick that's a Material Symbols name is the icon, when there's none.
  //   definition: { format, formatIcons,
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
      f[key] = s[key];
    const num = v => {
      const n = typeof v === "string" ? parseFloat(v) : v;
      return typeof n === "number" && isFinite(n) ? n : undefined;
    };
    const percentage = num(f.percentage);
    const textNumber = typeof f.text === "string" && /^\s*-?\d+(\.\d+)?\s*%?\s*$/.test(f.text) ? parseFloat(f.text) : undefined;
    let value = num(f.value) ?? (percentage === undefined ? textNumber : undefined);
    const icons = d.formatIcons;
    if ((f.alt === undefined || f.alt === null) && icons && typeof icons === "object" && !Array.isArray(icons) && typeof f.text === "string" && f.text.trim() in icons)
      f.alt = f.text.trim();
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
    // A Material Symbols name picked from format-icons draws as the icon
    if (!f.icon && /^[a-z][a-z0-9_]*$/.test(glyph))
      f.icon = glyph;
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
    const hidden = f.hidden === true || f.hidden === "true" || (d.hideEmpty !== false && rawText.trim() === "");
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
    // A number typed as the binding (a max of 100)
    if (/^-?\d+(\.\d+)?$/.test(b.trim()))
      return Number(b);
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

  // 0-1 for an element (elementRange), -1 without a value
  function elementRatio(fields, bind) {
    const r = root.elementRange(fields, bind);
    if (r.value === undefined)
      return -1;
    return r.max === r.min ? 0 : Math.max(0, Math.min(1, (r.value - r.min) / (r.max - r.min)));
  }

  // The element kinds a module is built from, in the editor's library
  // order: { type, label, icon, size ([w, h] sub-cells it's added at),
  // slots (its bindings), options (a properties schema for its look),
  // actions (the commands it runs) }. Labels and titles are English, the
  // editor translates them:
  // I18n.tr("Text") I18n.tr("Text block") I18n.tr("Icon")
  // I18n.tr("Ring") I18n.tr("Gauge") I18n.tr("Bar") I18n.tr("Segments")
  // I18n.tr("Sparkline") I18n.tr("List") I18n.tr("Image") I18n.tr("Button")
  // I18n.tr("Toggle") I18n.tr("Status") I18n.tr("Separator")
  // I18n.tr("Colour") I18n.tr("Default") I18n.tr("By state") I18n.tr("Accent")
  // I18n.tr("Second accent") I18n.tr("Text colour") I18n.tr("Dim text")
  // I18n.tr("Good") I18n.tr("Warning") I18n.tr("Error") I18n.tr("Info")
  // I18n.tr("Size") I18n.tr("Fit the box") I18n.tr("Small") I18n.tr("Normal")
  // I18n.tr("Large") I18n.tr("Huge") I18n.tr("Align") I18n.tr("Left")
  // I18n.tr("Centre") I18n.tr("Right") I18n.tr("Bold") I18n.tr("Monospace")
  // I18n.tr("Highest") I18n.tr("Step") I18n.tr("Inside")
  // I18n.tr("Percent") I18n.tr("Value") I18n.tr("None") I18n.tr("Blocks")
  // I18n.tr("Dots") I18n.tr("Source") I18n.tr("Material Symbols")
  // I18n.tr("Format icon") I18n.tr("Show the badge") I18n.tr("Fit")
  // I18n.tr("Crop") I18n.tr("Round") I18n.tr("Label") I18n.tr("Always a dot")
  // I18n.tr("Draw a line")
  readonly property var elementKinds: {
    const color = {
      "type": "string",
      "title": "Colour",
      "default": "",
      "enum": ["", "state", "accent", "accentAlt", "foreground", "foregroundAlt", "success", "warning", "error", "info"],
      "x-enumLabels": {
        "": "Default",
        "state": "By state",
        "accent": "Accent",
        "accentAlt": "Second accent",
        "foreground": "Text colour",
        "foregroundAlt": "Dim text",
        "success": "Good",
        "warning": "Warning",
        "error": "Error",
        "info": "Info"
      }
    };
    const flag = title => ({
          "type": "boolean",
          "title": title,
          "default": false
        });
    const text = title => ({
          "type": "string",
          "title": title,
          "default": ""
        });
    return [
      {
        "type": "Text",
        "label": "Text",
        "icon": "text_fields",
        "size": [12, 2],
        "slots": ["text"],
        "options": {
          "size": {
            "type": "string",
            "title": "Size",
            "default": "auto",
            "enum": ["auto", "small", "normal", "large", "huge"],
            "x-enumLabels": {
              "auto": "Fit the box",
              "small": "Small",
              "normal": "Normal",
              "large": "Large",
              "huge": "Huge"
            }
          },
          "align": {
            "type": "string",
            "title": "Align",
            "default": "center",
            "enum": ["left", "center", "right"],
            "x-enumLabels": {
              "left": "Left",
              "center": "Centre",
              "right": "Right"
            }
          },
          "bold": flag("Bold"),
          "monospace": flag("Monospace"),
          "color": color
        },
        "actions": []
      },
      {
        "type": "TextBlock",
        "label": "Text block",
        "icon": "notes",
        "size": [16, 8],
        "slots": ["text"],
        "options": {
          "monospace": flag("Monospace"),
          "color": color
        },
        "actions": []
      },
      {
        "type": "Icon",
        "label": "Icon",
        "icon": "star",
        "size": [4, 4],
        "slots": ["icon", "badge"],
        "options": {
          "source": {
            "type": "string",
            "title": "Source",
            "default": "material",
            "enum": ["material", "glyph"],
            "x-enumLabels": {
              "material": "Material Symbols",
              "glyph": "Format icon"
            }
          },
          "badge": flag("Show the badge"),
          "color": color
        },
        "actions": []
      },
      {
        "type": "Ring",
        "label": "Ring",
        "icon": "donut_large",
        "size": [6, 6],
        "slots": ["value", "min", "max", "label"],
        "options": ({
            "inside": {
              "type": "string",
              "title": "Inside",
              "default": "percent",
              "enum": ["percent", "value", "icon", "none"],
              "x-enumLabels": {
                "percent": "Percent",
                "value": "Value",
                "icon": "Icon",
                "none": "None"
              }
            },
            "color": color
          }),
        "actions": []
      },
      {
        "type": "Gauge",
        "label": "Gauge",
        "icon": "speed",
        "size": [6, 6],
        "slots": ["value", "min", "max", "label"],
        "options": ({
            "inside": {
              "type": "string",
              "title": "Inside",
              "default": "percent",
              "enum": ["percent", "value", "icon", "none"],
              "x-enumLabels": {
                "percent": "Percent",
                "value": "Value",
                "icon": "Icon",
                "none": "None"
              }
            },
            "color": color
          }),
        "actions": []
      },
      {
        "type": "Bar",
        "label": "Bar",
        "icon": "linear_scale",
        "size": [12, 2],
        "slots": ["value", "min", "max"],
        "options": ({
            "step": {
              "type": "number",
              "title": "Step",
              "default": 1
            },
            "color": color
          }),
        "actions": ["change"]
      },
      {
        "type": "Segments",
        "label": "Segments",
        "icon": "signal_cellular_alt",
        "size": [12, 2],
        "slots": ["value", "min", "max"],
        "options": ({
            "count": {
              "type": "integer",
              "title": "Blocks",
              "default": 5,
              "minimum": 2,
              "maximum": 24
            },
            "round": flag("Dots"),
            "color": color
          }),
        "actions": []
      },
      {
        "type": "Sparkline",
        "label": "Sparkline",
        "icon": "show_chart",
        "size": [12, 4],
        "slots": ["value"],
        "options": {
          "max": {
            "type": "number",
            "title": "Highest",
            "default": 0
          },
          "color": color
        },
        "actions": []
      },
      {
        "type": "List",
        "label": "List",
        "icon": "list",
        "size": [16, 8],
        "slots": ["items"],
        "options": {
          "color": color
        },
        "actions": []
      },
      {
        "type": "Image",
        "label": "Image",
        "icon": "image",
        "size": [6, 6],
        "slots": ["image"],
        "options": {
          "fit": {
            "type": "string",
            "title": "Fit",
            "default": "crop",
            "enum": ["crop", "fit"],
            "x-enumLabels": {
              "crop": "Crop",
              "fit": "Fit"
            }
          },
          "round": flag("Round")
        },
        "actions": []
      },
      {
        "type": "Button",
        "label": "Button",
        "icon": "smart_button",
        "size": [6, 2],
        "slots": ["label", "icon"],
        "options": {
          "label": text("Label"),
          "icon": text("Icon"),
          "color": color
        },
        "actions": ["click"]
      },
      {
        "type": "Toggle",
        "label": "Toggle",
        "icon": "toggle_on",
        "size": [10, 2],
        "slots": ["state", "label"],
        "options": {
          "label": text("Label")
        },
        "actions": ["on", "off"]
      },
      {
        "type": "Status",
        "label": "Status",
        "icon": "radio_button_checked",
        "size": [6, 2],
        "slots": ["text"],
        "options": {
          "dot": flag("Always a dot")
        },
        "actions": []
      },
      {
        "type": "Separator",
        "label": "Separator",
        "icon": "horizontal_rule",
        "size": [16, 1],
        "slots": [],
        "options": {
          "line": {
            "type": "boolean",
            "title": "Draw a line",
            "default": true
          }
        },
        "actions": []
      }
    ];
  }

  // An element kind's entry in elementKinds, or null
  function elementKind(type) {
    return root.elementKinds.find(k => k.type === type) ?? null;
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
  // I18n.tr("GPU load (NVIDIA)")
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

  // The elements drawn for a definition without any (a module never
  // shows empty): an icon, the text, and a ring when there's a value,
  // filling a lattice of `size`
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
        "options": {}
      });
    return out;
  }
}
