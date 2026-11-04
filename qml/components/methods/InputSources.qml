pragma Singleton
import QtQuick

// The input sources (Input.sources: xkb layouts and IME engines, `{ id,
// kind: "xkb" | "ime", layout, variant, engine }`) as each consumer takes
// them: the compositor's xkb list, fcitx5's group, ibus's engines, what a
// source switches to, which one is current and its label. An ime source
// types on the xkb layout it names (empty: the first xkb source's). The Go
// renderer ports xkb() (render.XkbLayouts), replaying its shared cases.
// `registry` is the xkb registry (the daemon's input.layouts: { layouts:
// [{ name, short, description, languages, variants: [{ name, short,
// description, languages }] }] }), or null.
QtObject {
  id: root

  // The layout written when no source names one
  readonly property string fallbackLayout: "us"

  // The compositor's xkb layouts: the xkb sources' distinct layout and
  // variant pairs in order, then any an ime source types on that none
  // has, as { layouts, variants, layout: "us,de", variant: "" or ",neo" }
  // (variant empty when no layout has one). Never empty: "us" alone
  function xkb(sources) {
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
      if (source?.kind === "ime" && root._text(source.layout) !== "")
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
    const first = root.xkb(sources);
    return {
      "layout": first.layouts[0],
      "variant": first.variants[0]
    };
  }

  // The index into xkb(sources).layouts `source` types on (-1 for none)
  function xkbIndex(sources, source) {
    const typing = root.typingLayout(sources, source);
    const list = root.xkb(sources);
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
    const first = root.xkb(sources);
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
