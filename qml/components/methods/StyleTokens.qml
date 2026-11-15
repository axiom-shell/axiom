pragma Singleton
import QtQuick

// Every colour role of the Style layer, derived from a theme in one pass
// (tokens.md; Style reads `derive`'s object once per theme change), the pure
// shape rules beside it (concentric radii, the text size floor) and the
// resolution of a theme's semantic map. The inner math runs on plain
// [r, g, b] arrays (Tone's *Rgb functions); colors are built only for the
// returned roles. docs/dev/core/style.md.
QtObject {
  id: root

  // ---- constants (tokens.md names each; the reference is tokens_reference.py) ----

  // targets are derived at min + margin (steps at min + margin / 2), so
  // rounding a colour to 8 bits never drops a pair under its minimum
  readonly property real margin: 0.05
  // contrast of faint text, of disabled text (WCAG exempts it), of the
  // lines, and of a floor's text over the pole
  readonly property real faintContrast: 3.0
  readonly property real disabledContrast: 2.0
  readonly property real dividerContrast: 1.12
  readonly property real subtleContrast: 1.12
  readonly property real strongContrast: 1.30
  readonly property real floorContrast: 3.0
  // surface against the page: [least, most] contrast, dark and light
  readonly property var surfaceStepDark: [1.08, 1.30]
  readonly property var surfaceStepLight: [1.06, 1.20]
  // raised against the card in dark themes; in light themes the least
  readonly property var raisedStepDark: [1.06, 1.20]
  readonly property real raisedApartLight: 1.04
  // highest against the card (light steps further: a 1.2 step read as no
  // button on a light card)
  readonly property var highestStepDark: [1.20, 1.60]
  readonly property var highestStepLight: [1.45, 1.90]
  // sunken against the card in light themes: a step darker (the dark
  // sunken is the page/card mix below, which measures at least 1.053)
  readonly property real sunkenApartLight: 1.07
  // how far sunken lies from the page toward the card in dark themes (the mix)
  readonly property real sunkenMix: 0.45
  // a light theme's sunken tone: the card mixed this far toward the text,
  // then moved apart from it
  readonly property real sunkenTextMix: 0.06
  // the lighter segment of a segmented control against the other
  readonly property real segmentThumbContrast: 1.25
  // how far the light raised surface lifts from the page toward white
  readonly property real raisedLightMix: 0.6
  // faint text: how far the foreground is mixed toward the card; disabled
  readonly property real faintMix: 0.5
  readonly property real disabledMix: 0.62
  // containers: how far the card is mixed toward the accent / a status
  readonly property real containerMixDark: 0.24
  readonly property real containerMixLight: 0.16
  readonly property real statusMixDark: 0.22
  readonly property real statusMixLight: 0.15
  // the on-colour of an accent container and of a status container: how far
  // the text is mixed toward the hue
  readonly property real onAccentContainerMix: 0.35
  readonly property real onStatusContainerMix: 0.4
  // lines: how far the page / the card is mixed toward the text
  readonly property real subtleMixDark: 0.12
  readonly property real subtleMixLight: 0.14
  readonly property real strongMix: 0.30
  readonly property real dividerMixDark: 0.10
  readonly property real dividerMixLight: 0.12
  // the accent rail beside a dependent row
  readonly property real railMix: 0.45
  // a solid fill's muted ink: the on-colour mixed toward the fill; a
  // container's muted and faint inks
  readonly property real solidMutedMix: 0.3
  readonly property real containerMutedMix: 0.25
  readonly property real containerFaintMix: 0.45
  // the opacity of a whole disabled control
  readonly property real opacityDisabled: 0.38
  // state layers (alpha of the text colour over a hovered / pressed / dragged
  // surface), dark then light
  readonly property real hoverDark: 0.08
  readonly property real hoverLight: 0.06
  readonly property real pressedDark: 0.14
  readonly property real pressedLight: 0.10
  readonly property real dragDark: 0.18
  readonly property real dragLight: 0.14
  // the same over an accent or status fill, in both variants
  readonly property real onAccentHover: 0.12
  readonly property real onAccentPressed: 0.20
  // modal dim inside a surface and the overlay's soft shadow
  readonly property real scrimDark: 0.45
  readonly property real scrimLight: 0.32
  readonly property real shadowSoftDark: 0.30
  readonly property real shadowSoftLight: 0.16
  // the veil over an image: least alpha (raised in 0.01 steps until the
  // text reads over mid grey), and the grey it is judged over
  readonly property real veilAlphaDark: 0.60
  readonly property real veilAlphaLight: 0.70
  readonly property real veilGrey: 128 / 255
  // the wash of a mark over content that must show through
  readonly property real washDark: 0.16
  readonly property real washLight: 0.14

  // ---- theme ----

  // A theme's resolved colours: { dark, semantic: { <name>: color }, names }.
  // Every name of defaults.semantic[variant] plus the theme's own extras
  // map through `themeData.semantic[name] ?? defaults.semantic[variant][name]`
  // to a base key (`themeData.colors[key] ?? defaults.colors[key]`), to
  // another semantic name, or are a colour themselves, as Theme._semantic
  // does. `names` is `semantic` plus base00-base0F: the closed map
  // Style.resolve reads. A null or unparsable `themeData` gives the
  // defaults' theme in the dark variant.
  function theme(themeData, defaults) {
    const data = themeData && typeof themeData === "object" ? themeData : {};
    const dark = data.variant !== "light";
    const defaultColors = defaults?.colors ?? {};
    const defaultSemantic = defaults?.semantic?.[dark ? "dark" : "light"] ?? {};
    const colors = Object.assign({}, defaultColors, data.colors ?? {});
    const own = data.semantic ?? {};
    const keys = Object.keys(defaultSemantic).concat(Object.keys(own).filter(name => !(name in defaultSemantic)));
    const pick = name => own[name] ?? defaultSemantic[name];
    const bases = ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07", "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"];
    const parse = value => {
      try {
        return Qt.color(value);
      } catch (e) {
        return null;
      }
    };
    const resolve = (name, depth) => {
      const key = pick(name);
      if (key === undefined || key === null)
        return null;
      if (bases.includes(key))
        return parse(colors[key] ?? defaultColors[key]);
      if (depth < 8 && key !== name && keys.includes(key))
        return resolve(key, depth + 1);
      return parse(key);
    };
    const semantic = {};
    for (const name of keys) {
      const c = resolve(name, 0);
      if (c)
        semantic[name] = c;
    }
    // what the derivation reads must exist, whatever the theme file holds
    const required = ["background", "backgroundAlt", "backgroundHighlight", "foreground", "foregroundAlt", "borderFocus", "accent", "accentAlt", "success", "warning", "error", "info", "cyan", "green", "yellow", "orange", "magenta", "red"];
    for (const name of required) {
      if (!semantic[name])
        semantic[name] = Qt.color("#808080");
    }
    const names = Object.assign({}, semantic);
    for (const base of bases) {
      const c = parse(colors[base] ?? defaultColors[base]);
      if (c)
        names[base] = c;
    }
    return {
      "dark": dark,
      "semantic": semantic,
      "names": names
    };
  }

  // The palette with its grey ramp reversed (base00 <-> base07, base01 <->
  // base06, base02 <-> base05, base03 <-> base04): the light fallback's
  // palette (ThemeManager), since theme-defaults' own is dark
  function reversedRamp(colors) {
    const ramp = ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07"];
    const out = Object.assign({}, colors);
    ramp.forEach((key, i) => {
      out[key] = colors[ramp[7 - i]];
    });
    return out;
  }

  // ---- shape rules ----

  // The radius of a highlight inset `inset` inside something of radius
  // `outer`, never under `min`
  function concentric(outer, inset, min) {
    return Math.max(min, outer - inset);
  }

  // A width that holds `n` characters at the default font: `n` px at
  // Interface scale `scale` (a factor), grown with the font setting
  // `baseFontSize` (equal to Math.round(n * scale) at 14)
  function textPx(n, scale, baseFontSize) {
    return Math.round(n * scale * baseFontSize / 14);
  }

  // A role's size: `Appearance.fontSizeBy(n)` at font setting `base` and
  // scale `scale`, never under 9 px at 100 % (on the scale) and never above
  // the body size
  function roleSize(n, base, scale) {
    return Math.max(Math.round((base + n) * scale), Math.min(Math.round(base * scale), Math.round(9 * scale)));
  }

  // ---- derivation ----

  // Every colour of tokens.md for `theme` (theme()'s result): one flat
  // object of the roles as colors, the alpha numbers, `alphaFloor`, `series`
  // (8 colors), `ink` ({ <tone>: { text, muted, faint, accent, icon,
  // graphic, divider } }), `segmentTrack`/`segmentThumb` (tone names),
  // `dark`, and `names`/`semantic` passed through.
  function derive(theme) {
    const dark = theme.dark;
    const g = name => Tone.rgb(theme.semantic[name]);
    const s = root._surfaces(g, dark);
    const t = root._texts(g, s);
    const text = t.text;
    const reading = s.reading;
    const nudged = (backs, c, min) => Tone.nudgedRgb(backs, c, min + root.margin);
    const apart = (base, c, min, pole) => Tone.apartRgb(base, c, min + root.margin / 2, pole);
    const black = [0, 0, 0];
    const out = {
      "dark": dark,
      "names": theme.names,
      "semantic": theme.semantic
    };
    const rgbs = {};
    const set = (name, c) => {
      rgbs[name] = c;
      out[name] = Tone.fromRgb(c);
    };
    set("surfacePage", s.page);
    set("surfaceSunken", s.sunken);
    set("surface", s.surface);
    set("surfaceRaised", s.raised);
    set("surfaceHighest", s.highest);
    set("text", text);
    set("textMuted", t.muted);
    set("textFaint", t.faint);
    set("textDisabled", nudged([s.surface], Tone.mixRgb(g("foreground"), s.surface, root.disabledMix), root.disabledContrast));
    set("textAccent", t.accent);
    // accent and status
    const containerMix = dark ? root.containerMixDark : root.containerMixLight;
    const statusMix = dark ? root.statusMixDark : root.statusMixLight;
    const accent = nudged(reading, g("accent"), Tone.iconContrast);
    set("accent", accent);
    set("onAccent", root._onColour(accent, s.page, [text]));
    set("accentContainer", Tone.mixRgb(s.surface, g("accent"), containerMix));
    set("onAccentContainer", nudged([rgbs.accentContainer], Tone.mixRgb(text, g("accent"), root.onAccentContainerMix), Tone.textContrast));
    set("accentAlt", nudged(reading, g("accentAlt"), Tone.iconContrast));
    for (const status of ["success", "warning", "error", "info"]) {
      const c = g(status);
      const name = status.charAt(0).toUpperCase() + status.slice(1);
      set(status, nudged(reading, c, Tone.iconContrast));
      set(status + "Text", nudged(reading, c, Tone.textContrast));
      set(status + "Container", Tone.mixRgb(s.surface, c, statusMix));
      set("on" + name, root._onColour(rgbs[status], s.page, [text]));
      set("on" + name + "Container", nudged([rgbs[status + "Container"]], Tone.mixRgb(text, c, root.onStatusContainerMix), Tone.textContrast));
    }
    out.series = ["accent", "accentAlt", "cyan", "green", "yellow", "orange", "magenta", "red"].map(name => Tone.fromRgb(nudged(reading, g(name), Tone.iconContrast)));
    // lines
    const subtleMix = dark ? root.subtleMixDark : root.subtleMixLight;
    const linePole = dark ? [1, 1, 1] : black;
    set("borderSubtle", apart(s.page, Tone.mixRgb(s.page, text, subtleMix), root.subtleContrast, linePole));
    set("borderStrong", nudged(reading, Tone.mixRgb(s.surface, text, root.strongMix), root.strongContrast));
    set("focusRing", nudged(reading, g("borderFocus"), Tone.iconContrast));
    set("rail", Tone.mixRgb(s.surface, g("accent"), root.railMix));
    // the theme's raw foreground: the screen frame and what joins it keep it
    set("frameStroke", g("foreground"));
    // inks (tokens.md > Contexts): what reads on each tone
    const dividerMix = dark ? root.dividerMixDark : root.dividerMixLight;
    const divider = (fill, inkText) => apart(fill, Tone.mixRgb(fill, inkText, dividerMix), root.dividerContrast, Tone.lumRgb(inkText) > Tone.lumRgb(fill) ? [1, 1, 1] : black);
    const makeInk = (text, muted, faint, accent, icon, graphic, fill) => ({
          "text": Tone.fromRgb(text),
          "muted": Tone.fromRgb(muted),
          "faint": Tone.fromRgb(faint),
          "accent": Tone.fromRgb(accent),
          "icon": Tone.fromRgb(icon),
          "graphic": Tone.fromRgb(graphic),
          "divider": Tone.fromRgb(divider(fill, text))
        });
    const neutralInk = fill => {
      const muted = nudged([fill], t.muted, Tone.textContrast);
      return makeInk(nudged([fill], text, Tone.textContrast), muted, nudged([fill], t.faint, root.faintContrast), nudged([fill], t.accent, Tone.textContrast), muted, nudged([fill], accent, Tone.iconContrast), fill);
    };
    const solidInk = (fill, on) => {
      const muted = nudged([fill], Tone.mixRgb(on, fill, root.solidMutedMix), Tone.iconContrast);
      return makeInk(on, muted, muted, on, on, on, fill);
    };
    const containerInk = (fill, on) => makeInk(on, nudged([fill], Tone.mixRgb(on, fill, root.containerMutedMix), Tone.textContrast), nudged([fill], Tone.mixRgb(on, fill, root.containerFaintMix), root.faintContrast), on, on, on, fill);
    const ink = {
      "page": neutralInk(s.page),
      "surface": neutralInk(s.surface),
      "sunken": neutralInk(s.sunken),
      "raised": neutralInk(s.raised),
      "highest": neutralInk(s.highest),
      "accent": solidInk(accent, rgbs.onAccent),
      "accentContainer": containerInk(rgbs.accentContainer, rgbs.onAccentContainer)
    };
    for (const status of ["success", "warning", "error", "info"]) {
      const name = status.charAt(0).toUpperCase() + status.slice(1);
      ink[status] = solidInk(rgbs[status], rgbs["on" + name]);
      ink[status + "Container"] = containerInk(rgbs[status + "Container"], rgbs["on" + name + "Container"]);
    }
    out.ink = ink;
    out.divider = ink.surface.divider;
    // the segmented control's tones: the thumb is always the lighter of the pair
    out.segmentTrack = dark ? "sunken" : "highest";
    out.segmentThumb = dark ? "highest" : "surface";
    // state layers and washes (colors with alpha) and the alpha numbers
    const alphas = {
      "alphaHover": dark ? root.hoverDark : root.hoverLight,
      "alphaPressed": dark ? root.pressedDark : root.pressedLight,
      "alphaDrag": dark ? root.dragDark : root.dragLight,
      "alphaOnAccentHover": root.onAccentHover,
      "alphaOnAccentPressed": root.onAccentPressed,
      "alphaScrim": dark ? root.scrimDark : root.scrimLight,
      "alphaShadowSoft": dark ? root.shadowSoftDark : root.shadowSoftLight,
      "alphaVeil": dark ? root.veilAlphaDark : root.veilAlphaLight,
      "alphaWash": dark ? root.washDark : root.washLight
    };
    // the veil's alpha: at least the variant's, raised until `text` over the
    // veil over mid grey reaches 4.5: only `text` is guaranteed over it
    const grey = [root.veilGrey, root.veilGrey, root.veilGrey];
    while (Tone.conRgb(text, Tone.mixRgb(grey, s.page, alphas.alphaVeil)) < Tone.textContrast + root.margin && alphas.alphaVeil < 1)
      alphas.alphaVeil = Math.round((alphas.alphaVeil + 0.01) * 100) / 100;
    Object.assign(out, alphas);
    out.opacityDisabled = root.opacityDisabled;
    const withAlpha = (c, a) => Qt.rgba(c[0], c[1], c[2], a);
    out.stateHover = withAlpha(text, alphas.alphaHover);
    out.statePressed = withAlpha(text, alphas.alphaPressed);
    out.stateDrag = withAlpha(text, alphas.alphaDrag);
    out.stateRest = withAlpha(text, 0);
    out.stateOnAccentHover = withAlpha(rgbs.onAccent, alphas.alphaOnAccentHover);
    out.stateOnAccentPressed = withAlpha(rgbs.onAccent, alphas.alphaOnAccentPressed);
    out.stateOnAccentRest = withAlpha(rgbs.onAccent, 0);
    out.scrim = withAlpha(black, alphas.alphaScrim);
    out.shadowSoft = withAlpha(black, alphas.alphaShadowSoft);
    out.veil = withAlpha(s.page, alphas.alphaVeil);
    out.accentWash = withAlpha(accent, alphas.alphaWash);
    out.errorWash = withAlpha(rgbs.error, alphas.alphaWash);
    out.alphaFloor = root._alphaFloor(rgbs, dark);
    return out;
  }

  // The nine roles a theme tile previews (tokens.md > Previews): the same
  // formulas as derive, without the status families and inks beyond the
  // card's divider
  function preview(theme) {
    const dark = theme.dark;
    const g = name => Tone.rgb(theme.semantic[name]);
    const s = root._surfaces(g, dark);
    const t = root._texts(g, s);
    const nudged = (backs, c, min) => Tone.nudgedRgb(backs, c, min + root.margin);
    const accent = nudged(s.reading, g("accent"), Tone.iconContrast);
    const containerMix = dark ? root.containerMixDark : root.containerMixLight;
    const accentContainer = Tone.mixRgb(s.surface, g("accent"), containerMix);
    const inkText = nudged([s.surface], t.text, Tone.textContrast);
    const dividerMix = dark ? root.dividerMixDark : root.dividerMixLight;
    const divider = Tone.apartRgb(s.surface, Tone.mixRgb(s.surface, inkText, dividerMix), root.dividerContrast + root.margin / 2, Tone.lumRgb(inkText) > Tone.lumRgb(s.surface) ? [1, 1, 1] : [0, 0, 0]);
    return {
      "surfacePage": Tone.fromRgb(s.page),
      "surface": Tone.fromRgb(s.surface),
      "text": Tone.fromRgb(t.text),
      "textMuted": Tone.fromRgb(t.muted),
      "accent": Tone.fromRgb(accent),
      "onAccent": Tone.fromRgb(root._onColour(accent, s.page, [t.text])),
      "accentContainer": Tone.fromRgb(accentContainer),
      "onAccentContainer": Tone.fromRgb(nudged([accentContainer], Tone.mixRgb(t.text, g("accent"), root.onAccentContainerMix), Tone.textContrast)),
      "divider": Tone.fromRgb(divider)
    };
  }

  // The five tonal surfaces and the four the content reads on
  function _surfaces(g, dark) {
    const step = (base, target, range, pole) => Tone.stepRgb(base, target, range[0] + root.margin / 2, range[1], pole);
    const page = g("background");
    const hi = g("backgroundHighlight");
    const pole = dark ? [1, 1, 1] : [0, 0, 0];
    const surface = step(page, g("backgroundAlt"), dark ? root.surfaceStepDark : root.surfaceStepLight, pole);
    const raised = dark ? step(surface, hi, root.raisedStepDark, [1, 1, 1]) : Tone.apartRgb(surface, Tone.mixRgb(page, [1, 1, 1], root.raisedLightMix), root.raisedApartLight + root.margin / 2, [1, 1, 1]);
    const highest = step(surface, hi, dark ? root.highestStepDark : root.highestStepLight, pole);
    const sunken = dark ? Tone.mixRgb(page, surface, root.sunkenMix) : Tone.apartRgb(surface, Tone.mixRgb(surface, g("foreground"), root.sunkenTextMix), root.sunkenApartLight + root.margin / 2, [0, 0, 0]);
    return {
      "page": page,
      "surface": surface,
      "sunken": sunken,
      "raised": raised,
      "highest": highest,
      "reading": [page, surface, sunken, raised]
    };
  }

  // The text roles on the four reading tones
  function _texts(g, s) {
    const nudged = (backs, c, min) => Tone.nudgedRgb(backs, c, min + root.margin);
    return {
      "text": nudged(s.reading, g("foreground"), Tone.textContrast),
      "muted": nudged(s.reading, g("foregroundAlt"), Tone.textContrast),
      "faint": nudged(s.reading, Tone.mixRgb(g("foreground"), s.surface, root.faintMix), root.faintContrast),
      "accent": nudged(s.reading, g("accent"), Tone.textContrast)
    };
  }

  // `preferred` on `background` where it reads at 4.5 + margin, else the
  // best of it, the alternates, black and white (the bar's readableOn with
  // the margin, so an 8-bit rounding never drops it under 4.5)
  function _onColour(background, preferred, alternates) {
    const ratio = c => Tone.conRgb(background, c);
    if (ratio(preferred) >= Tone.textContrast + root.margin)
      return preferred;
    return [preferred].concat(alternates, [[0, 0, 0], [1, 1, 1]]).reduce((best, c) => ratio(c) > ratio(best) ? c : best);
  }

  // The translucency floor (tokens.md > Translucency): the least surface
  // alpha at which `text` on each of the page and the card, over the
  // variant's opposite pole, reaches 3.0 (with half the margin); 0 when it
  // already reads on the pole. The larger, rounded up to 0.01.
  function _alphaFloor(rgbs, dark) {
    const pole = dark ? "#ffffff" : "#000000";
    const text = Tone.fromRgb(rgbs.text);
    if (Tone.contrast(text, pole) >= root.floorContrast)
      return 0;
    return ["surfacePage", "surface"].reduce((worst, name) => Math.max(worst, Tone.alphaFloor(Tone.fromRgb(rgbs[name]), text, [pole], root.floorContrast + root.margin / 2)), 0);
  }
}
