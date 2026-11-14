import QtQuick
import QtTest
import qs.components.methods

// The Style tokens (StyleTokens.theme / derive / preview) against the theme
// files: every guaranteed pair of tokens.md on every bundled theme, the two
// edge fixtures, the two fallback themes and the generated themes of the Go
// goldens; the committed reference values (tests/fixtures/style/expected.json,
// written by tokens_reference.py); and the pure shape rules.
TestCase {
  id: root

  name: "StyleTokens"

  RepoFiles {
    id: files
  }

  property var _defaults: null
  property var _themeFiles: ({})
  property var _generated: null

  // ---- loading ----

  function defaults() {
    if (!root._defaults)
      root._defaults = files.json("qml/config/json/theme-defaults.json");
    return root._defaults;
  }

  function bundled() {
    return files.json("tests/fixtures/style/themes.json");
  }

  function themeFile(name) {
    if (!root._themeFiles[name])
      root._themeFiles[name] = files.json(`qml/config/themes/${name}.json`);
    return root._themeFiles[name];
  }

  // ThemeManager._parseTheme's fallback, from theme-defaults.json alone
  function fallback(variant) {
    const d = defaults();
    return {
      "name": "Default (fallback)",
      "variant": variant,
      "colors": variant === "light" ? StyleTokens.reversedRamp(d.colors) : d.colors,
      "semantic": d.semantic[variant]
    };
  }

  // The generated themes of the Go goldens: [{ name, data }]
  function generated() {
    if (root._generated)
      return root._generated;
    const out = [];
    for (const file of ["accent", "bands", "gradient", "grey", "pixel"]) {
      const lines = files.text(`backend/internal/theme/palette/testdata/${file}.golden`).split("\n").filter(l => l.length > 0);
      for (const line of lines) {
        const space = line.indexOf(" ");
        const name = line.slice(0, space);
        const json = JSON.parse(line.slice(space + 1));
        out.push({
          "name": `gen:${file}:${name.replace(/\.json$/, "")}`,
          "data": {
            "variant": name.indexOf("-light") >= 0 ? "light" : "dark",
            "colors": json.colors,
            "semantic": {
              "accent": "base0D",
              "borderFocus": "base0D",
              "accentAlt": json.accentAlt ?? "base0E"
            }
          }
        });
      }
    }
    root._generated = out;
    return out;
  }

  // Every theme the pairs are asserted on: [{ name, data }]
  function allThemes() {
    const out = bundled().map(name => ({
          "name": name,
          "data": themeFile(name)
        }));
    out.push({
      "name": "flat-dark",
      "data": files.json("tests/fixtures/style/flat-dark.json")
    }, {
      "name": "flat-light",
      "data": files.json("tests/fixtures/style/flat-light.json")
    }, {
      "name": "fallback-dark",
      "data": fallback("dark")
    }, {
      "name": "fallback-light",
      "data": fallback("light")
    });
    return out.concat(generated());
  }

  function derived(data) {
    return StyleTokens.derive(StyleTokens.theme(data, defaults()));
  }

  // ---- colour helpers ----

  // A colour as the shell shows it: rounded to 8 bits
  function q(color) {
    return Qt.color(Qt.color(color).toString());
  }

  function con(a, b) {
    return Tone.contrast(root.q(a), root.q(b));
  }

  // The channels of a #rrggbb or #rrggbbaa (alpha last) string, 0-1
  function parseHex(hex) {
    const v = i => parseInt(hex.slice(i, i + 2), 16) / 255;
    return {
      "r": v(1),
      "g": v(3),
      "b": v(5),
      "a": hex.length > 7 ? v(7) : 1
    };
  }

  function near(actual, hex, message) {
    const c = Qt.color(actual);
    const e = root.parseHex(hex);
    verify(Math.abs(c.r - e.r) <= 1.5 / 255 && Math.abs(c.g - e.g) <= 1.5 / 255 && Math.abs(c.b - e.b) <= 1.5 / 255 && Math.abs(c.a - e.a) <= 1.5 / 255, `${message}: ${actual} != ${hex}`);
  }

  // ---- the guaranteed pairs (tokens.md) ----

  readonly property var toneFills: ({
      "page": "surfacePage",
      "surface": "surface",
      "sunken": "surfaceSunken",
      "raised": "surfaceRaised",
      "highest": "surfaceHighest",
      "accent": "accent",
      "accentContainer": "accentContainer",
      "success": "success",
      "successContainer": "successContainer",
      "warning": "warning",
      "warningContainer": "warningContainer",
      "error": "error",
      "errorContainer": "errorContainer",
      "info": "info",
      "infoContainer": "infoContainer"
    })

  readonly property var neutral: ["surfacePage", "surface", "surfaceSunken", "surfaceRaised"]
  readonly property var statuses: ["success", "warning", "error", "info"]

  function cap(s) {
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  // The static rows of tokens.md > Guaranteed pairs for one theme's roles:
  // [front, back, min, kind]. kind: "text" (>= min), "best" (the on-colour of
  // a solid fill: min where any candidate reaches it, else the best, at least
  // 3.0).
  function pairs(o) {
    const rows = [];
    for (const t of ["text", "textMuted", "textAccent"].concat(root.statuses.map(s => s + "Text"))) {
      for (const b of root.neutral)
        rows.push([t, b, 4.5, "text"]);
    }
    for (const b of root.neutral)
      rows.push(["textFaint", b, 3.0, "text"]);
    rows.push(["textDisabled", "surface", 2.0, "text"]);
    for (const t of ["accent", "accentAlt", "focusRing"].concat(root.statuses)) {
      for (const b of root.neutral)
        rows.push([t, b, 3.0, "text"]);
    }
    for (let i = 0; i < 8; i++) {
      for (const b of root.neutral)
        rows.push([`series[${i}]`, b, 3.0, "text"]);
    }
    rows.push(["onAccent", "accent", 4.5, "best"]);
    for (const s of root.statuses)
      rows.push(["on" + root.cap(s), s, 4.5, "best"]);
    rows.push(["onAccentContainer", "accentContainer", 4.5, "text"]);
    for (const s of root.statuses)
      rows.push(["on" + root.cap(s) + "Container", s + "Container", 4.5, "text"]);
    for (const tone of Object.keys(o.ink)) {
      const solid = tone === "accent" || root.statuses.indexOf(tone) >= 0;
      const container = tone.indexOf("Container") >= 0;
      const mins = {
        "text": 4.5,
        "muted": solid ? 3.0 : 4.5,
        "faint": solid ? 3.0 : 3.0,
        "accent": solid ? 3.0 : 4.5,
        "icon": solid || container ? 3.0 : 4.5,
        "graphic": 3.0
      };
      for (const k of Object.keys(mins))
        rows.push([`ink.${tone}.${k}`, root.toneFills[tone], mins[k], solid && ["text", "accent", "icon", "graphic"].indexOf(k) >= 0 ? "best" : "text"]);
      rows.push([`ink.${tone}.divider`, root.toneFills[tone], 1.12, "text"]);
    }
    const dark = o.dark;
    rows.push(["surface", "surfacePage", dark ? 1.08 : 1.06, "text"], ["surfaceHighest", "surface", dark ? 1.20 : 1.45, "text"], ["surfaceSunken", "surface", dark ? 1.05 : 1.04, "text"], ["segment.thumb", "segment.track", 1.25, "text"], ["borderSubtle", "surfacePage", 1.12, "text"]);
    for (const b of root.neutral)
      rows.push(["borderStrong", b, 1.30, "text"]);
    rows.push(["text", "veil@grey", 4.5, "text"], ["text", "floor@pole:surfacePage", 3.0, "text"], ["text", "floor@pole:surface", 3.0, "text"]);
    for (const t of ["sunken", "raised", "highest"])
      rows.push([`ink.${t}.text`, `nested@floor:${t}`, 3.0, "text"]);
    rows.push(["text", "shade@pole", 4.5, "text"], ["text", "shade@pole-dim", 4.5, "text"]);
    return rows;
  }

  // The colour a pair row names
  function value(o, key) {
    if (key.indexOf("segment.") === 0) {
      const tone = key === "segment.thumb" ? o.segmentThumb : o.segmentTrack;
      return o[root.toneFills[tone]];
    }
    if (key.indexOf("ink.") === 0) {
      const [, tone, k] = key.split(".");
      return o.ink[tone][k];
    }
    if (key.indexOf("series[") === 0)
      return o.series[parseInt(key.slice(7))];
    const pole = o.dark ? "#ffffff" : "#000000";
    if (key === "veil@grey")
      return Tone.over(o.veil, "#808080");
    if (key.indexOf("floor@pole:") === 0)
      return o.alphaFloor > 0 ? Tone.over(Tone.alpha(o[key.split(":")[1]], o.alphaFloor), pole) : o[key.split(":")[1]];
    if (key.indexOf("nested@floor:") === 0) {
      const a = o.alphaFloor;
      const fill = o[root.toneFills[key.split(":")[1]]];
      if (a === 0)
        return fill;
      const card = Tone.over(Tone.alpha(o.surface, a), pole);
      return Tone.over(Tone.alpha(fill, a), card);
    }
    if (key === "shade@pole" || key === "shade@pole-dim") {
      // the shade of the unknown tone: the page at the least alpha that
      // reads over the pole (under the lock's 40 % dim for the second)
      const back = key === "shade@pole" ? pole : Tone.mix(pole, "#000000", 0.4);
      const a = Tone.alphaFloor(o.surfacePage, o.text, [back], Tone.textContrast + StyleTokens.margin);
      return Tone.over(Tone.alpha(o.surfacePage, a), back);
    }
    return o[key];
  }

  function checkPair(o, front, back, min, kind) {
    const ratio = root.con(root.value(o, front), root.value(o, back));
    if (kind === "best") {
      const fill = root.value(o, back);
      const best = Math.max(Tone.contrast(fill, o.surfacePage), Tone.contrast(fill, o.text), Tone.contrast(fill, "#000000"), Tone.contrast(fill, "#ffffff"));
      return [ratio >= min - 1e-9 || (ratio >= 3.0 && ratio >= best - 0.01), ratio];
    }
    return [ratio >= min - 1e-9, ratio];
  }

  // ---- theme resolution ----

  function test_theme_matches_theme_files() {
    const d = defaults();
    for (const name of bundled()) {
      const file = themeFile(name);
      const t = StyleTokens.theme(file, d);
      const variant = file.variant === "light" ? "light" : "dark";
      compare(t.dark, variant === "dark", name);
      for (const key of Object.keys(d.semantic[variant])) {
        const base = file.semantic?.[key] ?? d.semantic[variant][key];
        const hex = file.colors?.[base] ?? d.colors[base] ?? base;
        verify(Qt.colorEqual(t.semantic[key], hex), `${name}.${key}: ${t.semantic[key]} != ${hex}`);
      }
    }
  }

  function test_theme_fallbacks() {
    const d = defaults();
    for (const data of [null, undefined, "nonsense", 7]) {
      const t = StyleTokens.theme(data, d);
      compare(t.dark, true, "a missing theme is the dark defaults");
      verify(Qt.colorEqual(t.semantic.background, d.colors.base00));
      verify(StyleTokens.derive(t).surfacePage !== undefined, "derive never returns undefined");
    }
  }

  function test_names() {
    // Theme.qml's stringToColorMap (45 names), copied: this pure test can't read Theme
    const listed = ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07", "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F", "background", "backgroundAlt", "backgroundHighlight", "foreground", "foregroundAlt", "foregroundHighlight", "foregroundInactive", "border", "borderFocus", "accent", "accentAlt", "success", "warning", "error", "info", "red", "green", "yellow", "blue", "magenta", "cyan", "orange", "grey", "bg0", "bg1", "bg2", "fg3", "fg2", "fg1"];
    compare(listed.length, 45);
    const d = defaults();
    for (const name of bundled()) {
      const file = themeFile(name);
      const variant = file.variant === "light" ? "light" : "dark";
      const names = StyleTokens.theme(file, d).names;
      for (const key of listed.concat(["white", "bg3"])) {
        const base = /^base0[0-9A-F]$/.test(key) ? key : (file.semantic?.[key] ?? d.semantic[variant][key]);
        const hex = file.colors?.[base] ?? d.colors[base] ?? base;
        verify(names[key] !== undefined && Qt.colorEqual(names[key], hex), `${name}.${key}: ${names[key]} != ${hex}`);
      }
    }
  }

  // ---- the pair sweep ----

  function test_contrast_targets() {
    const failures = [];
    let checked = 0;
    let rows = 0;
    const all = allThemes();
    compare(all.length, 42 + 2 + 2 + 50, "42 bundled, 2 edge fixtures, 2 fallbacks, 50 generated");
    for (const theme of all) {
      const o = derived(theme.data);
      const list = pairs(o);
      rows = list.length;
      for (const [front, back, min, kind] of list) {
        const [ok, ratio] = checkPair(o, front, back, min, kind);
        checked++;
        if (!ok)
          failures.push(`${theme.name}: ${front} on ${back} = ${ratio.toFixed(2)} (min ${min})`);
      }
    }
    compare(rows, 223 + 2, "the static rows (223) and the two unknown-tone shade rows");
    compare(failures, [], `${failures.length} of ${checked} pairs fail`);
  }

  function test_translucent_roles() {
    for (const theme of allThemes()) {
      const o = derived(theme.data);
      const dark = o.dark;
      verify(o.alphaVeil >= (dark ? 0.60 : 0.70) - 1e-9, `${theme.name}: veil alpha ${o.alphaVeil}`);
      verify(con(o.text, Tone.over(o.veil, "#808080")) >= 4.5, `${theme.name}: text over the veil over grey`);
      // a color's alpha is held in 8 bits
      verify(Math.abs(o.veil.a - o.alphaVeil) <= 0.5 / 255 + 1e-6, `${theme.name}: veil alpha`);
      const wash = dark ? 0.16 : 0.14;
      verify(Math.abs(o.accentWash.a - wash) <= 0.5 / 255 + 1e-6 && Math.abs(o.errorWash.a - wash) <= 0.5 / 255 + 1e-6, `${theme.name}: wash alpha`);
      verify(Qt.colorEqual(Qt.alpha(o.accentWash, 1), o.accent), `${theme.name}: accentWash is the accent`);
      verify(Qt.colorEqual(Qt.alpha(o.errorWash, 1), o.error), `${theme.name}: errorWash is the error`);
      verify(Qt.colorEqual(o.frameStroke, o.semantic.foreground), `${theme.name}: frameStroke is the raw foreground`);
      verify(Qt.colorEqual(o.surfacePage, o.semantic.background), `${theme.name}: surfacePage is the raw background`);
      compare(o.stateRest.a, 0, theme.name);
      compare(o.stateOnAccentRest.a, 0, theme.name);
    }
  }

  function test_reference_values() {
    const expected = files.json("tests/fixtures/style/expected.json");
    compare(expected.order.length, 4);
    for (const name of expected.order) {
      const e = expected.themes[name];
      const o = derived(themeFile(name));
      compare(o.dark, e.dark, name);
      for (const key of Object.keys(e.roles))
        near(o[key], e.roles[key], `${name}.${key}`);
      for (let i = 0; i < 8; i++)
        near(o.series[i], e.series[i], `${name}.series[${i}]`);
      for (const key of Object.keys(e.translucent))
        near(o[key], e.translucent[key], `${name}.${key}`);
      for (const key of Object.keys(e.alphas))
        verify(Math.abs(o[key] - e.alphas[key]) < 1e-6, `${name}.${key}: ${o[key]} != ${e.alphas[key]}`);
      verify(Math.abs(o.alphaFloor - e.alphaFloor) < 1e-6, `${name}.alphaFloor: ${o.alphaFloor} != ${e.alphaFloor}`);
      for (const tone of Object.keys(e.ink)) {
        for (const key of Object.keys(e.ink[tone]))
          near(o.ink[tone][key], e.ink[tone][key], `${name}.ink.${tone}.${key}`);
      }
    }
  }

  function test_variants() {
    for (const theme of allThemes()) {
      const o = derived(theme.data);
      const lum = c => Tone.luminance(c);
      if (o.dark) {
        verify(lum(o.surface) > lum(o.surfacePage), `${theme.name}: a dark card lighter than the page`);
        verify(con(o.surfaceHighest, o.surface) >= 1.20, `${theme.name}: highest vs surface`);
      } else {
        // a light card is darker than the page, unless the theme's own
        // backgroundAlt is the lighter (tokyo-day): the card follows it
        if (lum(o.semantic.backgroundAlt) <= lum(o.semantic.background))
          verify(lum(o.surface) < lum(o.surfacePage), `${theme.name}: a light card darker than the page`);
        verify(lum(o.surfaceRaised) > lum(o.surface), `${theme.name}: a light raised surface lighter than the card`);
        verify(con(o.surfaceHighest, o.surface) >= 1.45, `${theme.name}: highest vs surface`);
      }
      compare(o.alphaHover, o.dark ? 0.08 : 0.06, theme.name);
      compare(o.alphaPressed, o.dark ? 0.14 : 0.10, theme.name);
      compare(o.alphaDrag, o.dark ? 0.18 : 0.14, theme.name);
      compare(o.alphaScrim, o.dark ? 0.45 : 0.32, theme.name);
      compare(o.alphaShadowSoft, o.dark ? 0.30 : 0.16, theme.name);
      compare(o.alphaWash, o.dark ? 0.16 : 0.14, theme.name);
      compare(o.segmentTrack, o.dark ? "sunken" : "highest", theme.name);
      compare(o.segmentThumb, o.dark ? "highest" : "surface", theme.name);
    }
  }

  function test_concentric() {
    const rows = [[12, 4, 3, 8], [4, 4, 3, 3], [0, 4, 0, 0], [12, 0, 3, 12], [6, 10, 2, 2], [8, 3, 3, 5]];
    for (const [outer, inset, min, expected] of rows)
      compare(StyleTokens.concentric(outer, inset, min), expected, `${outer} - ${inset}, min ${min}`);
  }

  function test_text_px() {
    for (const n of [400, 260, 100, 37, 9]) {
      for (let percent = 75; percent <= 150; percent++) {
        const scale = percent / 100;
        compare(StyleTokens.textPx(n, scale, 14), Math.round(n * scale), `${n} at ${percent} %`);
      }
    }
    compare(StyleTokens.textPx(400, 1, 28), 800, "grows with the font size");
    compare(StyleTokens.textPx(400, 1, 7), 200, "and shrinks with it");
  }

  function test_size_floor() {
    for (let base = 8; base <= 32; base++) {
      for (let percent = 75; percent <= 150; percent += 5) {
        const scale = percent / 100;
        const body = Math.round(base * scale);
        for (const n of [-3, -2]) {
          const size = StyleTokens.roleSize(n, base, scale);
          verify(size <= body, `${n} at font ${base}, ${percent} %: ${size} above body ${body}`);
          verify(size >= Math.min(body, Math.round(9 * scale)), `${n} at font ${base}, ${percent} %: ${size} under the floor`);
        }
        verify(StyleTokens.roleSize(-3, base, scale) <= StyleTokens.roleSize(-2, base, scale), `micro above caption at font ${base}`);
      }
    }
    compare(StyleTokens.roleSize(-3, 14, 1), 11, "micro at the defaults");
    compare(StyleTokens.roleSize(-2, 14, 1), 12, "caption at the defaults");
    compare(StyleTokens.roleSize(-3, 12, 1), 9, "unchanged from font 12");
  }

  function test_fallback_themes() {
    for (const variant of ["dark", "light"]) {
      const o = derived(fallback(variant));
      compare(o.dark, variant === "dark");
      for (const [front, back, min, kind] of pairs(o)) {
        const [ok, ratio] = checkPair(o, front, back, min, kind);
        verify(ok, `${variant} fallback: ${front} on ${back} = ${ratio.toFixed(2)} (min ${min})`);
      }
    }
    const light = derived(fallback("light"));
    verify(Tone.luminance(light.surfacePage) > Tone.luminance(light.text), "the light fallback's page is lighter than its text");
  }

  function test_reversed_ramp() {
    const d = defaults();
    const r = StyleTokens.reversedRamp(d.colors);
    const ramp = ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07"];
    ramp.forEach((key, i) => compare(r[key], d.colors[ramp[7 - i]], key));
    for (const key of ["base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"])
      compare(r[key], d.colors[key], key);
    compare(d.colors.base00, "#0c0c0c", "the input is not changed");
  }

  function test_generated_themes() {
    compare(generated().length, 50);
    for (const theme of generated()) {
      const o = derived(theme.data);
      for (const [front, back, min, kind] of pairs(o)) {
        const [ok, ratio] = checkPair(o, front, back, min, kind);
        verify(ok, `${theme.name}: ${front} on ${back} = ${ratio.toFixed(2)} (min ${min})`);
      }
    }
  }

  function test_alpha_floor() {
    // tokens_reference.py --floors
    const rows = [["catppuccin-mocha", 0.66], ["catppuccin-latte", 0.69], ["gruvbox-dark", 0.74], ["tokyo-night", 0.69]];
    for (const [name, expected] of rows) {
      const o = derived(themeFile(name));
      verify(Math.abs(o.alphaFloor - expected) <= 0.01, `${name}: ${o.alphaFloor} != ${expected}`);
      const pole = o.dark ? "#ffffff" : "#000000";
      verify(con(o.text, Tone.over(Tone.alpha(o.surfacePage, o.alphaFloor), pole)) >= 3.0, `${name}: text on the page at the floor over the pole`);
    }
  }

  // The distance of two colours in OKLab
  function oklab(color) {
    const c = Qt.color(color);
    const lin = v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    const r = lin(c.r), g = lin(c.g), b = lin(c.b);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
  }

  function test_collisions_listed() {
    const listed = files.json("tests/fixtures/style/collisions.json");
    const found = [];
    for (const name of bundled()) {
      const sem = StyleTokens.theme(themeFile(name), defaults()).semantic;
      const a = oklab(sem.accent);
      const hit = root.statuses.some(s => {
        const b = oklab(sem[s]);
        return Math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) < 0.05;
      });
      if (hit)
        found.push(name);
    }
    compare(found, listed, "themes whose accent is within 0.05 (OKLab) of a status colour");
  }

  function test_preview_matches_derive() {
    for (const theme of allThemes()) {
      const t = StyleTokens.theme(theme.data, defaults());
      const full = StyleTokens.derive(t);
      const cut = StyleTokens.preview(t);
      compare(Object.keys(cut).length, 9, theme.name);
      for (const key of Object.keys(cut))
        verify(Qt.colorEqual(cut[key], full[key]), `${theme.name}.${key}: ${cut[key]} != ${full[key]}`);
    }
  }

  // Nothing creates Style yet, so the shell can't log its derive: measure it
  // here (tokens.md > Performance 1: the budget is 4 ms for the costliest)
  function test_derive_time() {
    for (const name of ["everforest-light", "catppuccin-mocha", "catppuccin-latte", "gruvbox-dark", "tokyo-night"]) {
      const t = StyleTokens.theme(themeFile(name), defaults());
      StyleTokens.derive(t);
      const start = Date.now();
      for (let i = 0; i < 20; i++)
        StyleTokens.derive(StyleTokens.theme(themeFile(name), defaults()));
      const mean = (Date.now() - start) / 20;
      console.log(`StyleTokens.derive ${name}: ${mean} ms over 20`);
      verify(mean < 20, `${name}: ${mean} ms`);
    }
    // the theme list's previews: every bundled theme, once
    const start = Date.now();
    for (const name of bundled())
      StyleTokens.preview(StyleTokens.theme(themeFile(name), defaults()));
    const took = Date.now() - start;
    console.log(`StyleTokens.preview ${bundled().length} bundled themes: ${took} ms`);
    verify(took < 300, `${took} ms`);
  }
}
