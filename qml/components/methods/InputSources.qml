pragma Singleton
import QtQuick

// The input sources (Input.sources: xkb layouts and IME engines, `{ id,
// kind: "xkb" | "ime", layout, variant, engine }`) as each consumer takes
// them: the compositor's xkb list, fcitx5's group, ibus's engines, what a
// source switches to, which one is current and its label. An ime source
// types on the xkb layout it names (empty: the first xkb source's). The Go
// renderer ports xkb() (render.XkbLayouts) and methodSetup() (render.
// InputMethodEnv / InputMethodCommand), replaying their shared cases.
// `registry` is the xkb registry (the daemon's input.layouts: { layouts:
// [{ name, short, description, languages, variants: [{ name, short,
// description, languages }] }] }), or null.
QtObject {
  id: root

  // The layout written when no source names one
  readonly property string fallbackLayout: "us"

  // The compositor's xkb layouts: the xkb sources' distinct layout and
  // variant pairs in order, then (with `engines`: axiom manages the input
  // method, Input.method.enabled) any an ime source types on that none
  // has, as { layouts, variants, layout: "us,de", variant: "" or ",neo" }
  // (variant empty when no layout has one). Never empty: "us" alone. The
  // other helpers take the sources they're given as counting (a caller
  // drops the engines while off: xkbOnly)
  function xkb(sources, engines) {
    const list = Array.isArray(sources) ? sources : [];
    const pairs = [];
    const add = (layout, variant) => {
      if (layout !== "" && !pairs.some(p => p.layout === layout && p.variant === variant))
        pairs.push({
          "layout": layout,
          "variant": variant
        });
    };
    for (const source of list)
      if (source?.kind === "xkb")
        add(root._text(source.layout), root._text(source.variant));
    for (const source of list)
      if (engines === true && source?.kind === "ime" && root._text(source.layout) !== "")
        add(root._text(source.layout), root._text(source.variant));
    if (pairs.length === 0)
      add(root.fallbackLayout, "");
    const variants = pairs.map(p => p.variant);
    return {
      "layouts": pairs.map(p => p.layout),
      "variants": variants,
      "layout": pairs.map(p => p.layout).join(","),
      "variant": variants.some(v => v !== "") ? variants.join(",") : ""
    };
  }

  // The xkb layout `source` types on, { layout, variant }: its own, or
  // for an ime source naming none the first xkb pair
  function typingLayout(sources, source) {
    const own = root._text(source?.layout);
    if (own !== "")
      return {
        "layout": own,
        "variant": root._text(source.variant)
      };
    const first = root.xkb(sources, true);
    return {
      "layout": first.layouts[0],
      "variant": first.variants[0]
    };
  }

  // The index into xkb(sources).layouts `source` types on (-1 for none)
  function xkbIndex(sources, source) {
    const typing = root.typingLayout(sources, source);
    const list = root.xkb(sources, true);
    for (let i = 0; i < list.layouts.length; i++)
      if (list.layouts[i] === typing.layout && list.variants[i] === typing.variant)
        return i;
    return -1;
  }

  // fcitx5's name for `source`: keyboard-<layout>[-<variant>] for an xkb
  // one, the engine for an ime one
  function fcitx5Name(source) {
    if (source?.kind === "ime")
      return root._text(source.engine);
    return "keyboard-" + root._fcitx5Layout(source?.layout, source?.variant);
  }

  // fcitx5's input method group for the sources ({ defaultLayout, items:
  // [{ name, layout }] }, SetInputMethodGroupInfo's): each source with the
  // layout it types on, as fcitx5 writes one ("de-neo")
  function fcitx5Group(sources) {
    const list = (Array.isArray(sources) ? sources : []).filter(s => root._usable(s));
    const first = root.xkb(sources, true);
    return {
      "defaultLayout": root._fcitx5Layout(first.layouts[0], first.variants[0]),
      "items": list.map(source => {
        const typing = root.typingLayout(sources, source);
        return {
          "name": root.fcitx5Name(source),
          "layout": root._fcitx5Layout(typing.layout, typing.variant)
        };
      })
    };
  }

  // ibus's name for `source`: xkb:<layout>:<variant>:<language> for an
  // xkb one (the language the registry gives the variant, else its layout,
  // else empty), the engine for an ime one
  function ibusName(source, registry) {
    if (source?.kind === "ime")
      return root._text(source.engine);
    const layout = root._text(source?.layout);
    const variant = root._text(source?.variant);
    const entry = root._entry(registry, layout, variant);
    const languages = (entry.variant?.languages ?? []).length > 0 ? entry.variant.languages : entry.layout?.languages ?? [];
    return "xkb:" + layout + ":" + variant + ":" + (languages[0] ?? "");
  }

  // ibus's engines for the sources (its preload-engines), in order
  function ibusEngines(sources, registry) {
    return (Array.isArray(sources) ? sources : []).filter(s => root._usable(s)).map(s => root.ibusName(s, registry));
  }

  // The input method `source` is under `framework` ("fcitx5", "ibus", or
  // anything else for none: "")
  function imName(source, framework, registry) {
    if (framework === "fcitx5")
      return root.fcitx5Name(source);
    if (framework === "ibus")
      return root.ibusName(source, registry);
    return "";
  }

  // What switching to the source `id` sets: { xkbIndex, im } (im "" under
  // no framework), or null when no source has that id
  function target(sources, id, framework, registry) {
    const source = (Array.isArray(sources) ? sources : []).find(s => s?.id === id && root._usable(s));
    if (!source)
      return null;
    return {
      "xkbIndex": root.xkbIndex(sources, source),
      "im": root.imName(source, framework, registry)
    };
  }

  // The id of the current source, from the compositor's xkb index and the
  // framework's current input method (`im`, "" when none runs): the source
  // that is that input method (of two, the one on that index), else the
  // first xkb source on that index, else any on it; "" for none
  function current(sources, xkbIndex, im, framework, registry) {
    const list = (Array.isArray(sources) ? sources : []).filter(s => root._usable(s));
    const index = Number(xkbIndex) || 0;
    const onIndex = s => root.xkbIndex(sources, s) === index;
    if (String(im ?? "") !== "" && (framework === "fcitx5" || framework === "ibus")) {
      const named = list.filter(s => root.imName(s, framework, registry) === im);
      const pick = named.find(onIndex) ?? named[0];
      if (pick)
        return pick.id;
    }
    const pick = list.find(s => s.kind === "xkb" && onIndex(s)) ?? list.find(onIndex);
    return pick ? pick.id : "";
  }

  // The full name of an xkb layout and variant ("German (Neo 2)"), from
  // the registry; the code ("de", "de neo") without it
  function describe(registry, layout, variant) {
    const entry = root._entry(registry, root._text(layout), root._text(variant));
    const own = root._text(variant) !== "" ? entry.variant?.description : entry.layout?.description;
    return own || [root._text(layout), root._text(variant)].filter(t => t !== "").join(" ");
  }

  // What a source is shown as: an ime source its engine's own label
  // (`engineLabel`, "あ", from the framework) or its engine name; an xkb
  // one its layout code ("de") with `format` "code", its full name
  // (describe) with "name"
  function label(source, format, registry, engineLabel) {
    if (source?.kind === "ime")
      return String(engineLabel ?? "") || root._text(source.engine);
    if (format === "name")
      return root.describe(registry, source?.layout, source?.variant);
    return root._text(source?.layout);
  }

  // The sources to switch between, in order: the usable ones of
  // `sources`; while the compositor's xkb layouts (`layouts`, codes from
  // withKeyboard, empty while unknown) aren't what axiom writes for them
  // (xkb(sources, engines): axiom doesn't set the keyboard, the
  // compositor's own config does), its xkb part is an xkb source per
  // layout the compositor has ("xkb:<index>:<code>"), then the ime
  // sources. Give it every source, as the compositor's list is written
  // from: a caller leaving some out (engines no framework runs) does so
  // after
  function effective(sources, layouts, engines) {
    const list = (Array.isArray(sources) ? sources : []).filter(s => root._usable(s));
    const codes = (Array.isArray(layouts) ? layouts : []).map(code => root._text(code));
    if (codes.length === 0 || JSON.stringify(root.xkb(list, engines).layouts) === JSON.stringify(codes))
      return list;
    return codes.map((code, i) => ({
          "id": "xkb:" + i + ":" + code,
          "kind": "xkb",
          "layout": code,
          "variant": "",
          "engine": ""
        })).concat(list.filter(s => s.kind === "ime"));
  }

  // The xkb sources alone (what a password field types through)
  function xkbOnly(sources) {
    return (Array.isArray(sources) ? sources : []).filter(s => s?.kind === "xkb" && root._usable(s));
  }

  // The id of the source after (`direction` 1) or before (-1) the one
  // `id` names in `sources`, wrapping; the first (or the last) when `id`
  // isn't there, "" with none
  function step(sources, id, direction) {
    const list = (Array.isArray(sources) ? sources : []).filter(s => root._usable(s));
    if (list.length === 0)
      return "";
    const at = list.findIndex(s => s.id === id);
    const back = Number(direction) < 0;
    if (at < 0)
      return back ? list[list.length - 1].id : list[0].id;
    return list[(at + (back ? -1 : 1) + list.length) % list.length].id;
  }

  // Whether the framework's list (the daemon's inputMethod state: {
  // defaultLayout, group: [{ name, layout }] }) is the sources': fcitx5's
  // default layout, names and layouts (an item's empty layout being the
  // default one), ibus's names. True under no framework
  function groupMatches(framework, sources, registry, state) {
    const group = Array.isArray(state?.group) ? state.group : [];
    if (framework === "ibus")
      return JSON.stringify(group.map(item => root._text(item?.name))) === JSON.stringify(root.ibusEngines(sources, registry));
    if (framework !== "fcitx5")
      return true;
    const wanted = root.fcitx5Group(sources);
    const fallback = root._text(state?.defaultLayout);
    const have = group.map(item => ({
          "name": root._text(item?.name),
          "layout": root._text(item?.layout) || fallback
        }));
    return fallback === wanted.defaultLayout && JSON.stringify(have) === JSON.stringify(wanted.items);
  }

  // The framework's list (as groupMatches takes it) as sources, for a
  // draft of Input.sources: fcitx5's keyboard-<layout>[-<variant>] and
  // ibus's xkb:<layout>:<variant>:<language> are xkb sources, anything
  // else an engine, typing on its item's layout (fcitx5; empty when that's
  // the default one, so it follows the first). Ids from the layout or the
  // engine, made unique
  function fromGroup(framework, state) {
    const group = Array.isArray(state?.group) ? state.group : [];
    const fallback = root._text(state?.defaultLayout);
    const taken = [];
    const named = base => {
      let id = base || "source";
      for (let n = 2; taken.includes(id); n++)
        id = (base || "source") + n;
      taken.push(id);
      return id;
    };
    const sources = [];
    for (const item of group) {
      const name = root._text(item?.name);
      if (name === "")
        continue;
      let xkb = null;
      if (framework === "fcitx5" && name.startsWith("keyboard-"))
        xkb = root._splitFcitx5(name.slice("keyboard-".length));
      else if (framework === "ibus" && name.startsWith("xkb:")) {
        const parts = name.split(":");
        xkb = {
          "layout": parts[1] ?? "",
          "variant": parts[2] ?? ""
        };
      }
      if (xkb && xkb.layout !== "") {
        sources.push({
          "id": named(xkb.variant !== "" ? xkb.layout + "-" + xkb.variant : xkb.layout),
          "kind": "xkb",
          "layout": xkb.layout,
          "variant": xkb.variant,
          "engine": ""
        });
        continue;
      }
      const layout = framework === "fcitx5" && root._text(item?.layout) !== fallback ? root._splitFcitx5(root._text(item?.layout)) : {
        "layout": "",
        "variant": ""
      };
      sources.push({
        "id": named(name.replace(/[^A-Za-z0-9_-]/g, "-")),
        "kind": "ime",
        "layout": layout.layout,
        "variant": layout.layout !== "" ? layout.variant : "",
        "engine": name
      });
    }
    return sources;
  }

  // The registry's layouts and variants whose name or code holds `query`
  // (any case), as [{ layout, variant, description }], a layout before
  // its variants, at most `limit` (the settings' layout picker); none
  // without a registry
  function searchLayouts(registry, query, limit) {
    const words = root._text(query).toLowerCase().split(/\s+/).filter(w => w !== "");
    const max = Number(limit) > 0 ? Number(limit) : 50;
    const out = [];
    const holds = text => words.every(w => text.toLowerCase().includes(w));
    for (const entry of registry?.layouts ?? []) {
      const layout = root._text(entry?.name);
      if (layout === "")
        continue;
      const description = root._text(entry.description) || layout;
      const rows = [
        {
          "layout": layout,
          "variant": "",
          "description": description
        }
      ].concat((entry.variants ?? []).filter(v => root._text(v?.name) !== "").map(v => ({
            "layout": layout,
            "variant": root._text(v.name),
            "description": root._text(v.description) || description + " (" + root._text(v.name) + ")"
          })));
      for (const row of rows) {
        if (!holds([row.layout, row.variant, row.description].join(" ")))
          continue;
        out.push(row);
        if (out.length >= max)
          return out;
      }
    }
    return out;
  }

  // An id for a new source in `sources`: `base` with what an id can't
  // hold made "-", numbered when one has it already ("de", "de2")
  function freeId(sources, base) {
    const taken = (Array.isArray(sources) ? sources : []).map(s => String(s?.id ?? ""));
    const clean = root._text(base).replace(/[^A-Za-z0-9._-]/g, "-").replace(/^[^A-Za-z0-9]+/, "") || "source";
    let id = clean;
    for (let n = 2; taken.includes(id); n++)
      id = clean + n;
    return id;
  }

  // What a framework needs where axiom doesn't write the compositor's
  // config (the Input method settings' intro): the session's variables
  // ([{ name, value }]; `legacyApps` adds GTK_IM_MODULE / QT_IM_MODULE)
  // and the command starting it, as the managed session's writer has them
  // (render.InputMethodEnv / InputMethodCommand, which replay these cases
  // through Shared). Empty for anything but "fcitx5" and "ibus"
  function methodSetup(framework, legacyApps) {
    if (framework !== "fcitx5" && framework !== "ibus")
      return {
        "env": [],
        "command": ""
      };
    const env = {
      "fcitx5": [["XMODIFIERS", "@im=fcitx"], ["QT_IM_MODULES", "wayland;fcitx;ibus"], ["SDL_IM_MODULE", "fcitx"], ["GLFW_IM_MODULE", "ibus"]],
      "ibus": [["XMODIFIERS", "@im=ibus"], ["QT_IM_MODULES", "wayland;ibus"], ["SDL_IM_MODULE", "ibus"], ["GLFW_IM_MODULE", "ibus"]]
    }[framework];
    const module = framework === "fcitx5" ? "fcitx" : "ibus";
    const pairs = legacyApps === true ? env.concat([["GTK_IM_MODULE", module], ["QT_IM_MODULE", module]]) : env;
    return {
      "env": pairs.map(p => ({
            "name": p[0],
            "value": p[1]
          })),
      "command": framework === "fcitx5" ? "fcitx5 -d --replace" : "ibus-daemon -drxR"
    };
  }

  // fcitx5's "de-neo" as { layout, variant }
  function _splitFcitx5(text) {
    const at = text.indexOf("-");
    return at < 0 ? {
      "layout": text,
      "variant": ""
    } : {
      "layout": text.slice(0, at),
      "variant": text.slice(at + 1)
    };
  }

  // A source that names what it is (an xkb layout, an engine)
  function _usable(source) {
    return source?.kind === "ime" ? root._text(source.engine) !== "" : source?.kind === "xkb" && root._text(source.layout) !== "";
  }

  function _fcitx5Layout(layout, variant) {
    const v = root._text(variant);
    return root._text(layout) + (v !== "" ? "-" + v : "");
  }

  // The registry's { layout, variant } entries (each undefined when not
  // listed)
  function _entry(registry, layout, variant) {
    const entry = (registry?.layouts ?? []).find(l => l?.name === layout);
    return {
      "layout": entry,
      "variant": variant !== "" ? (entry?.variants ?? []).find(v => v?.name === variant) : undefined
    };
  }

  function _text(value) {
    return String(value ?? "").trim();
  }
}
