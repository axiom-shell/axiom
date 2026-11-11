pragma Singleton
import QtQuick

// Paint: which color each part of a bar widget, or of a cell inside one
// (a workspace), takes on a bar's look (BarLook.resolve, barConfig.look)
// for its state. What a style is (boxed, filled on hover, what takes the
// gradient, …) is the look's traits; this only colors.
//
// `palette` is the look's colors resolved once (palette(),
// barConfig.palette): barText (what reads on the bar itself: the theme's
// foreground), background (the theme's background), override
// (the bar's text color, replacing the automatic one, or null),
// labelColor (split's label color, or null), group and groupStroke (a
// merged run's background and outline), gradientStops (the bar
// gradient's colors, or null), and the bar's other colors resolved once:
// separator (the dividers between widgets), accentLine ({ from, to }, the
// bar's accent line, or null), hoverOutline (a hovered widget's outline)
// and cellHover (a hovered cell's box). A user's color is taken as set,
// never graded.
//
// `state` is what of the widget itself its colors depend on (state()):
//   splits    it shows an icon part and a label apart (split: an icon or a
//             lead graphic, and a label); without, a split bar draws it
//             filled (the style's `fallback`)
//   hovered   the pointer is over it (its hit area): a tinted or outlined
//             widget then draws as filled (Fill on hover)
//   gradient  the bar gradient's color where it sits (its middle), or
//             null: no gradient (or no place on a bar, a preview)
//   auto      its color is an Auto field that gives way to the bar's
//             gradient (`x-autoGradient`, `accent` implied;
//             BarsConfig.withAutoColors). A color set on the widget and
//             the state colors that don't give way keep theirs.
//   run       it's a merged run's own background (runColors)
//   group     it sits in a merged run, which draws its background
//   solid     (a cell) a filled box whatever the bar's style
//   level     it draws a pill level (the widget's background filled to
//             its value), which its content must read on too
//   muted     it is dimmed: its accent mixed toward the bar's background
//             (mutedMix), and content that doesn't sit on a fill mixed
//             toward its backdrop and floored at mutedContrast, in the
//             place of any opacity (an off lock key, a paused timer)
//   pressed   it is pressed: its content mixed pressMix toward its
//             backdrop, then nudged back to its floor
//   pulse     (a cell) 0-1, how far it is toward its muted self (cell)
//   hover     (a cell) the color of its hover box, or null: the
//             palette's cellHover
//   under     (a cell) what the widget's text sits on (its `textBack`), the
//             cell's own content reading on it; none: the bar
//
// Content (text, icons, graphics, badges) is nudged to be readable: mixed
// toward white or black by the least that reaches 4.5 for text and 3 for
// the rest, against what it sits on (`textBack`, `iconBack`: opaque
// colors, a tint or translucent fill composited over the bar's
// background). A state colour that replaces the override (colorText) and a
// widget's own content colours are still nudged; the override itself
// (palette.override) never is, unless it is muted or pressed. Fills,
// strokes and lines are never nudged.
QtObject {
  id: root

  // WCAG contrast the content must reach: text, and icons and graphics
  readonly property real textContrast: 4.5
  readonly property real iconContrast: 3
  // Muted: how far its color is mixed toward its backdrop, and the
  // contrast it keeps there; an empty cell's mix; and how far a press
  // mixes content toward its backdrop
  readonly property real mutedMix: 0.45
  readonly property real mutedContrast: 3
  readonly property real emptyMix: 0.6
  readonly property real pressMix: 0.2

  // The look's colors resolved (`palette` above): `resolve` maps a color
  // name to a color (Theme.resolveColor); `barText` reads on the bar (the
  // theme's foreground), `background` is the theme's
  function palette(look, resolve, barText, background) {
    const line = look.accentLine;
    return {
      "barText": barText,
      "background": background,
      "override": look.textColor ? resolve(look.textColor) : null,
      "labelColor": look.split ? resolve(look.split.labelColor) : null,
      "group": resolve(look.group.color),
      "groupStroke": resolve(look.group.strokeColor),
      "gradientStops": look.gradient ? look.gradient.map(name => resolve(name)) : null,
      "separator": resolve(look.separators.color),
      "accentLine": line ? {
        "from": resolve(line.color),
        "to": line.fade ? resolve(line.fade) : resolve(line.color)
      } : null,
      "hoverOutline": resolve("border"),
      "cellHover": resolve("backgroundHighlight")
    };
  }

  // A widget's or cell's `state` (above) from what of it its look
  // depends on, each left out false or none: `spot`, where its middle
  // sits along the bar (0-1, -1 for nowhere: BarGradient.spot), stands for
  // `gradient`
  function state(palette, widget) {
    const spot = widget?.spot ?? -1;
    const stops = spot >= 0 ? palette.gradientStops : null;
    return {
      "gradient": stops ? BarGradient.gradientAt(stops, spot) : null,
      "splits": widget?.splits === true,
      "hovered": widget?.hovered === true,
      "auto": widget?.auto === true,
      "run": widget?.run === true,
      "group": widget?.group === true,
      "solid": widget?.solid === true,
      "level": widget?.level === true,
      "under": widget?.under ?? null,
      "muted": widget?.muted === true,
      "pressed": widget?.pressed === true,
      "pulse": widget?.pulse ?? 0,
      "hover": widget?.hover ?? null
    };
  }

  // `a` mixed `t` (0-1) of the way to `b`, every channel
  function mix(a, b, t) {
    const x = Qt.color(a);
    const y = Qt.color(b);
    return Qt.rgba(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, x.a + (y.a - x.a) * t);
  }

  // `color` mixed `t` toward `back`, its alpha kept (a clear color stays
  // clear)
  function _toward(color, back, t) {
    const c = Qt.color(color);
    if (c.a === 0)
      return color;
    const m = root.mix(c, back, t);
    return Qt.rgba(m.r, m.g, m.b, c.a);
  }

  // `color` dimmed to sit back on `backs` (opaque colors): mixed mutedMix
  // toward the first, then nudged to read at least mutedContrast on all
  function muted(backs, color) {
    return root.nudged(backs, root._toward(color, backs[0], root.mutedMix), root.mutedContrast);
  }

  // `a` mixed `t` of the way to `b`, each color in them (colors() or
  // cell() results: a pulse between a widget and its muted self); the
  // rest of `a` kept. Their backdrops (lists of colors) are mixed too.
  // Content that differs is nudged again to mutedContrast on those, as a
  // mix of two colors that read can fall short.
  function mixColors(a, b, t) {
    if (t <= 0)
      return a;
    if (t >= 1)
      return b;
    const isColor = v => (typeof v === "string" && /^(#[0-9a-fA-F]+|transparent)$/.test(v)) || (typeof v === "object" && v !== null && typeof v === "object" && v.r !== undefined);
    const out = {};
    for (const key in a) {
      const x = a[key];
      const y = b[key];
      if (isColor(x) && isColor(y))
        out[key] = Qt.colorEqual(x, y) ? x : root.mix(x, y, t);
      else if (Array.isArray(x) && Array.isArray(y) && x.length === y.length && x.every(isColor))
        out[key] = x.map((c, i) => root.mix(c, y[i], t));
      else if (x !== null && typeof x === "object" && !Array.isArray(x) && y !== null && typeof y === "object" && x.r === undefined)
        out[key] = root.mixColors(x, y, t);
      else
        out[key] = x;
    }
    const backs = {
      "text": "textBack",
      "icon": "iconBack",
      "headText": "iconBack",
      "mark": "iconBack",
      "content": "back"
    };
    for (const key in backs)
      if (key in out && out[backs[key]] && !Qt.colorEqual(out[key], a[key]) && !Qt.colorEqual(out[key], b[key]))
        out[key] = root.nudged(out[backs[key]], out[key], root.mutedContrast);
    if (out.graphic && out.iconBack)
      out.graphic.line = root.nudged(out.iconBack, out.graphic.line, root.mutedContrast);
    return out;
  }

  // A color of a widget's own field as it is drawn (a state color, a
  // mark's, a part's): the gradient's color at `spot` (0-1, -1 for none)
  // where it `givesWay` to it (an Auto field, active) and the bar has
  // one, else `color`. Under the bar's text color (palette.override) a
  // neutral or active field (`role`) takes it; a warning or critical one
  // keeps its own. The caller nudges it (content()).
  function fieldColor(palette, spot, color, givesWay, role) {
    if (palette.override !== null && (role === "neutral" || role === "active"))
      return palette.override;
    if (givesWay && spot >= 0 && palette.gradientStops)
      return BarGradient.gradientAt(palette.gradientStops, spot);
    return color;
  }

  // A badge's { fill, text } in `color`: the fill read on what the icon
  // part sits on and the bar (`colors`, colors(); contrast iconContrast),
  // its text what reads on it (readableOn, the palette's colors)
  function badge(palette, colors, color) {
    const fill = root.nudged(colors.iconBack.concat([root._opaque(palette.background)]), color, root.iconContrast);
    return {
      "fill": fill,
      "text": root.readableOn(root.over(fill, palette.background), palette.barText, [palette.background])
    };
  }

  // `top` drawn over `under`, as an opaque color (`under` taken opaque)
  function over(top, under) {
    const t = Qt.color(top);
    const u = Qt.color(under);
    return Qt.rgba(t.r * t.a + u.r * (1 - t.a), t.g * t.a + u.g * (1 - t.a), t.b * t.a + u.b * (1 - t.a), 1);
  }

  // `color` where it reads on every one of `backs` (opaque colors; WCAG
  // contrast at least `min`), else mixed toward white or black, whichever
  // reads better on them, by the least that does, its hue kept; the pole
  // itself where no mix does. Its alpha is kept; a clear color stays as it is.
  function nudged(backs, color, min) {
    const c = Qt.color(color);
    const worst = x => backs.reduce((least, b) => Math.min(least, Utils.contrast(b, x)), Infinity);
    if (c.a === 0 || worst(c) >= min)
      return color;
    const white = Qt.rgba(1, 1, 1, c.a);
    const black = Qt.rgba(0, 0, 0, c.a);
    const pole = worst(white) >= worst(black) ? white : black;
    const mix = t => Qt.rgba(c.r + (pole.r - c.r) * t, c.g + (pole.g - c.g) * t, c.b + (pole.b - c.b) * t, c.a);
    if (worst(pole) < min)
      return pole;
    let low = 0;
    let high = 1;
    for (let i = 0; i < 12; i++) {
      const middle = (low + high) / 2;
      if (worst(mix(middle)) >= min)
        high = middle;
      else
        low = middle;
    }
    return mix(high);
  }

  // What a widget draws in: { fill, stroke, indicator, text, icon,
  // iconFill, gradient, textOnFill, textBack, iconBack, iconOnFill,
  // level, accent, headText, mark, graphic, override, muted, pressed }.
  // `accent` (the result's): its color for its state as drawn: the
  // gradient's where it gives way, else its own (muted, where it is). The
  // `accent` argument is its own color for its state (its background
  // while filled), `own` its text color (picked to read on that
  // background). `iconFill` is split's icon part (its icon or
  // badge), else transparent; `gradient` what of its background draws the
  // bar's gradient ({ part, alpha }: the look's `gradientPart` trait), else
  // null. `textOnFill`: its text sits on a fill it must read on (filled; in
  // a merged run on a filled or split bar, the run's; split's label on a
  // color of its own; filled on hover), so it never takes a state's color
  // (stateContent). `textBack` and `iconBack` are the opaque colors the
  // text and the icon sit on (lists: a pill's level adds a second), which
  // `text` and `icon` are nudged to read on; `iconOnFill`: the icon sits on
  // a fill it must read on too; `level`: the pill's color, from the icon's.
  // `headText`: the text of its icon part (the icon's color, read at the
  // text's floor on `iconBack`); `mark`: a mark's neutral color (the
  // icon's); `graphic` { line, track, area, caption } what a ring, bar or
  // sparkline draws in, all opaque (its line the icon's).
  // `override`, `muted` and `pressed` are the palette's and state's, which
  // content() reads; `textOwnFill` and `iconOwnFill`: the text or the icon
  // sits on the widget's own fill (a muted one leaves such content to its
  // fill; one on a merged run's is dimmed itself).
  function colors(look, palette, state, accent, own) {
    const graded = state.gradient !== null && state.auto;
    const base = graded ? state.gradient : accent;
    const color = state.muted ? root._toward(base, root._opaque(palette.background), root.mutedMix) : base;
    const result = root._widget(look, palette, state, color, root._readable(palette, color, own), graded);
    result.gradient = graded ? root._widgetGradient(look, state) : null;
    result.accent = color;
    return root._finish(palette, state, result);
  }

  // What a bar widget draws in on its bar (colors() on the bar's look and
  // palette, `barConfig`: an enriched bar): `accent` is its color for its
  // state, `own` the text color it's configured with (resolved), `widget`
  // what of the widget itself its look depends on (state()'s: splits,
  // hovered, spot, auto, level; left out, none of it). In a merged run on
  // a merged bar.
  function widgetColors(barConfig, accent, own, widget) {
    const palette = barConfig.palette;
    return root.colors(barConfig.look, palette, root.state(palette, {
      "splits": widget?.splits,
      "hovered": widget?.hovered,
      "spot": widget?.spot,
      "auto": widget?.auto,
      "level": widget?.level,
      "group": barConfig.look.grouping === "merged",
      "muted": widget?.muted,
      "pressed": widget?.pressed
    }), accent, own);
  }

  // `result` (_widget's) with its level color from its icon, its
  // backdrops under the level where it draws one, and its text, icon and
  // the rest of its content read on them (_read)
  function _finish(palette, state, result) {
    result.level = root._level(state, result);
    if (state.level) {
      result.textBack = result.textBack.concat(result.textBack.map(b => root.over(result.level, b)));
      result.iconBack = result.iconBack.concat(result.iconBack.map(b => root.over(result.level, b)));
    }
    const flags = {
      "override": palette.override,
      "muted": state.muted,
      "pressed": state.pressed
    };
    const head = result.icon;
    result.textOwnFill = result.textOnFill && Qt.color(result.fill).a > 0;
    result.iconOwnFill = result.iconOnFill && (Qt.color(result.fill).a > 0 || Qt.color(result.iconFill).a > 0);
    result.text = root._read(flags, result.textBack, result.text, root.textContrast, result.textOwnFill);
    result.headText = root._read(flags, result.iconBack, head, root.textContrast, result.iconOwnFill);
    result.icon = root._read(flags, result.iconBack, result.icon, root.iconContrast, result.iconOwnFill);
    result.mark = result.icon;
    result.graphic = root._graphic(result.iconBack, result.icon, result.text);
    Object.assign(result, flags);
    return result;
  }

  // `color` as content that sits on `backs` (opaque): at least `min`
  // contrast on all of them. The bar's text color (`flags.override`) is
  // never nudged, but for a muted or pressed one. Muted (`flags.muted`),
  // content not on the widget's own fill (`onFill`; one on a run's is) is dimmed (muted(), floor
  // mutedContrast); pressed, mixed pressMix toward the first backdrop and
  // nudged back to its floor.
  function _read(flags, backs, color, min, onFill) {
    const fixed = flags.override !== null && Qt.colorEqual(color, flags.override);
    const dimmed = flags.muted && !onFill;
    let c = color;
    if (dimmed)
      c = root.muted(backs, c);
    if (flags.pressed)
      c = root._toward(c, backs[0], root.pressMix);
    if (fixed && !dimmed && !flags.pressed)
      return c;
    return root.nudged(backs, c, dimmed ? root.mutedContrast : min);
  }

  // The pill's level color: the icon's, faded to 35%. Where the widget
  // draws a level, content must read on it as well as on what it sits on,
  // so where no pole (white or black) does with the icon's color, a white
  // or black sheen at the same strength (a lighter or darker shade of the
  // fill's own hue), the one the text doesn't use first; else the icon's
  // color weaker, by the most that does.
  function _level(state, result) {
    const plain = root.faded(result.icon, 0.35);
    if (!state.level)
      return plain;
    const poles = ["#ffffff", "#000000"];
    const reads = level => [result.textBack, result.iconBack].every(backs => poles.some(p => backs.every(b => Utils.contrast(b, p) >= root.textContrast && Utils.contrast(root.over(level, b), p) >= root.textContrast)));
    if (reads(plain))
      return plain;
    const text = Utils.contrast(result.textBack[0], "#ffffff") >= Utils.contrast(result.textBack[0], "#000000") ? "#ffffff" : "#000000";
    const sheens = [text === "#ffffff" ? "#000000" : "#ffffff", text].map(p => Qt.alpha(p, 0.35));
    const sheen = sheens.find(reads);
    if (sheen !== undefined)
      return sheen;
    let low = 0;
    let high = 0.35;
    for (let i = 0; i < 12; i++) {
      const middle = (low + high) / 2;
      if (reads(root.faded(result.icon, middle)))
        low = middle;
      else
        high = middle;
    }
    return root.faded(result.icon, low);
  }

  // What a ring, bar or sparkline draws in, all opaque: its `line` (on
  // `backs`), a `track` and an `area` of it faded over them, and its
  // `caption` (text over it, `text`'s)
  function _graphic(backs, line, text) {
    return {
      "line": root.over(line, backs[0]),
      "track": root.over(root.faded(line, 0.2), backs[0]),
      "area": root.over(root.faded(line, 0.35), backs[0]),
      "caption": root.over(text, backs[0])
    };
  }

  // What a merged run's shared background draws in (colors() as the run):
  // its group color (an outline run's line its stroke color), or with a
  // gradient on the bar one strip of it (`spot`: the run's middle, -1 for
  // none)
  function runColors(look, palette, spot) {
    const group = look.traits.stroke ? palette.groupStroke : palette.group;
    return root.colors(look, palette, root.state(palette, {
      "spot": spot,
      "auto": true,
      "run": true
    }), group, root._readable(palette, group, palette.barText));
  }

  // A cell inside a widget (a workspace) in the same look: { fill, stroke,
  // indicator, content, showsHover, gradient }; a solid one (`state.solid`)
  // is a filled box whatever the bar's style, its outline and line (where
  // the bar draws them) its color too. `color` is the cell's color for its
  // state, `own` what reads on it filled, `cellState` "active" |
  // "occupied" | "urgent" | "empty". Where the content sits on the bar
  // rather than on the cell's color, an empty cell's is the bar's text
  // dimmed (its own color is meant to barely show), and plain text tells
  // the states apart by fading alone, but for an urgent cell, whose
  // content takes its color. `showsHover`: hovered, it's filled (Fill on
  // hover), so the cell draws no hover box of its own. An Auto color
  // (`state.auto`) gives way to the bar gradient's where the cell sits, as
  // a widget's does. In a merged run (`state.group`) the run draws the
  // background, as for a widget: a cell whose style's `groupCell` trait
  // holds draws no box, its color moving to its content (an empty one's
  // faded, reading on the run); a solid cell stays a filled box, and a
  // split one fills its box, a tab in the row as a widget that doesn't
  // split (the `boxedInRun` trait).
  // `back`: the opaque colors its content sits on; `hover`: its hover
  // box's color (state.hover, else the palette's cellHover). A muted cell
  // (`state.muted`) is dimmed as a widget is; an empty one's content is
  // always mixed emptyMix toward its backdrop, floored at mutedContrast.
  // With a `state.pulse`, it is that far between itself and its muted self.
  function cell(look, palette, state, color, own, cellState) {
    if (state.pulse > 0) {
      const rest = root.cell(look, palette, Object.assign({}, state, {
        "pulse": 0
      }), color, own, cellState);
      const dimmed = root.cell(look, palette, Object.assign({}, state, {
        "pulse": 0,
        "muted": true
      }), color, own, cellState);
      return root.mixColors(rest, dimmed, state.pulse);
    }
    const graded = state.gradient !== null && state.auto;
    const base = graded ? state.gradient : color;
    const fill = state.muted ? root._toward(base, root._opaque(palette.background), root.mutedMix) : base;
    const result = root._cell(look, palette, state, fill, root._readable(palette, fill, own), cellState);
    result.gradient = graded ? root._cellGradient(look, state, result) : null;
    result.hover = state.hover ?? palette.cellHover;
    if (state.muted && !result.onFill)
      result.content = root.muted(result.back, result.content);
    return result;
  }

  // The traits a widget draws in: its look's, or its style's `fallback`'s
  // where it can't draw that (split's, for a widget that doesn't split)
  function _drawn(look, state) {
    return root._fallback(look, look.traits, !state.splits);
  }

  // The traits a cell draws in: a solid box's or its look's (cellTraits),
  // their `fallback`'s where they have one (split's filled: a cell has no
  // label apart)
  function _cellDrawn(look, state) {
    return root._fallback(look, BarLook.cellTraits(look, state.solid), true);
  }

  function _fallback(look, traits, falls) {
    return traits.fallback && falls ? BarLook.traitsOf(traits.fallback, look) : traits;
  }

  // Whether a box drawn in `traits` holds its content on its own fill
  // (the `box` trait's text reads on its color), so a merged run of them
  // is a fill its labels read on too
  function _onFill(traits) {
    return traits.box?.text === "own";
  }

  // A box drawn in `traits` (their `box` trait) in `color` and what reads
  // in it, before the bar's text color: { fill, stroke, indicator, text,
  // icon, onFill, keepsIcon }. `onFill`: the content reads on the box's
  // own fill (`own`), not on the bar; `keepsIcon`: the icon keeps its
  // color under the bar's text color (colored icons: it carries the
  // state). `unfilled` is an unfilled box's fill: its color cleared where
  // it fills on hover, so the fill fades in from nothing rather than
  // through black. A widget's and a cell's boxes are the same; an icon
  // part and a label apart (iconPart) are the widget's alone (_widget).
  function _box(traits, look, palette, color, own, unfilled) {
    const b = traits.box;
    const of = role => {
      switch (role) {
      case "color":
        return color;
      case "tint":
        return root.faded(color, look.tint);
      case "unfilled":
        return unfilled;
      case "own":
        return own;
      case "bar":
        return palette.barText;
      default:
        return "transparent";
      }
    };
    return {
      "fill": of(b.fill),
      "stroke": of(b.stroke),
      "indicator": of(b.indicator),
      "text": of(b.text),
      "icon": of(b.icon),
      "onFill": root._onFill(traits),
      "keepsIcon": b.keepsIcon,
      "fillRole": b.fill
    };
  }

  function _widget(look, palette, state, accent, own, graded) {
    const none = "transparent";
    const text = c => palette.override ?? c;
    const drawn = root._drawn(look, state);
    const fills = look.hoverFill;
    const unfilled = fills ? Qt.alpha(accent, 0) : none;
    // What content sits on, opaque: the bar, a color over it, a tint of
    // the accent over it
    const bar = [root._opaque(palette.background)];
    const on = c => [root.over(c, bar[0])];
    const tint = on(root.faded(accent, look.tint));
    if (state.hovered && fills)
      // Filled in its own color, its text and icon reading on it; an
      // outline keeps its stroke (unseen on the fill) so it doesn't fade
      // out and back. In a merged run, the widget's own part alone
      return root._make(accent, drawn.stroke && !state.group ? accent : none, none, text(own), text(own), none, true, on(accent), on(accent), true);
    if (state.run && graded && look.traits.runTints)
      // A split run's strip of the gradient is its labels' tint, under
      // icon parts each in their own slice of it
      return root._make(root.faded(accent, look.tint), none, none, text(own), text(own), none, false, tint, tint, false);
    if (state.group) {
      // The run draws the background: the icon keeps the state, the label
      // reads on the run (or on the bar, through a tint or outline). A
      // split icon part keeps its own fill on the run, its label on the
      // run's color, or on a gradient's tint in the widget's color. On a
      // gradient run the run's color is the gradient's where the widget
      // sits, and an Auto icon reads on it as the label does (through a
      // tint or outline it takes that color)
      // (A split run with a gradient is its labels' tint, not a fill)
      if (drawn.iconPart)
        return root._make(none, none, none, text(state.gradient ? accent : root._readable(palette, palette.group, palette.barText)), text(own), accent, !state.gradient, state.gradient ? tint : on(palette.group), on(accent), true);
      if (look.traits.boxedInRun)
        // One that doesn't split fills its own box in the run, a tab in
        // the row of them
        return root._make(accent, none, none, text(own), text(own), none, true, on(accent), on(accent), true);
      const group = state.gradient ?? palette.group;
      const onRun = root._onFill(drawn);
      const label = text(onRun ? root._readable(palette, group, palette.barText) : palette.barText);
      return root._make(unfilled, none, none, label, graded && onRun ? label : accent, none, onRun, onRun ? on(group) : bar, onRun ? on(group) : bar, onRun);
    }
    if (drawn.iconPart) {
      // The icon part filled, the label on a tint of it, on a color of
      // its own (reading on it) or on the bar; a badge's always on the bar
      const label = look.split.label;
      if (label === "color")
        return root._make(palette.labelColor, none, none, text(root._readable(palette, palette.labelColor, palette.barText)), text(own), accent, true, on(palette.labelColor), on(accent), true);
      return root._make(label === "tint" ? root.faded(accent, look.tint) : none, none, none, text(accent), text(own), accent, false, label === "tint" ? tint : bar, on(accent), true);
    }
    const box = root._box(drawn, look, palette, accent, own, unfilled);
    const back = box.fillRole === "color" ? on(accent) : box.fillRole === "tint" ? tint : bar;
    return root._make(box.fill, box.stroke, box.indicator, text(box.text), box.keepsIcon ? box.icon : text(box.icon), none, box.onFill, back, back, box.fillRole === "color");
  }

  // What of a widget's background takes the bar's gradient: filled on
  // hover, its fill in full; a run's strip that tints (runTints), at the
  // tint; in a merged run (which draws it) none, but for an icon part or
  // the box of one boxed in the run; else its drawn traits' `gradientPart`
  function _widgetGradient(look, state) {
    const drawn = root._drawn(look, state);
    if (state.hovered && look.hoverFill)
      return root._part("fill", 1);
    if (state.run && look.traits.runTints)
      return root._part("fill", look.tint);
    if (state.group)
      return drawn.iconPart ? root._part("iconFill", 1) : look.traits.boxedInRun ? root._part("fill", 1) : null;
    return drawn.gradientPart;
  }

  function _cell(look, palette, state, color, own, cellState) {
    const none = "transparent";
    const text = c => palette.override ?? c;
    const traits = BarLook.cellTraits(look, state.solid);
    const drawn = root._cellDrawn(look, state);
    const fills = look.hoverFill && traits.hoverFills;
    const merged = state.group && traits.groupCell;
    // What the content sits on, opaque: the run's color where it's filled,
    // else the bar (through a tint or an outline)
    const under = merged && root._onFill(drawn) ? root._readable(palette, palette.group, palette.barText) : palette.barText;
    // Behind it, opaque: what the widget's text sits on (`state.under`,
    // else the bar), or the run's fill; its state color is nudged to read
    // there (not under the bar's text color), over its box's fill
    const behind = merged && root._onFill(drawn) ? [root.over(palette.group, palette.background)] : state.under ?? [root._opaque(palette.background)];
    const over = (c, backs) => backs.map(b => root.over(c, b));
    if (state.hovered && fills)
      return root._makeCell(color, drawn.stroke && !state.group ? color : none, none, text(own), true, true, over(color, behind));
    const nudge = (c, backs) => root.nudged(backs, c, root.textContrast);
    // An empty cell's content: the text mixed toward what it sits on
    const empty = backs => root.nudged(backs, root._toward(text(under), backs[0], root.emptyMix), root.mutedContrast);
    const onBar = (c, backs) => cellState === "empty" ? empty(backs) : palette.override ?? nudge(c, backs);
    const unfilled = fills ? Qt.alpha(color, 0) : none;
    if (merged)
      return root._makeCell(unfilled, none, none, onBar(color, behind), false, false, behind);
    const box = root._box(drawn, look, palette, color, own, unfilled);
    if (!drawn.colored)
      return root._makeCell(box.fill, box.stroke, box.indicator, cellState === "active" ? text(palette.barText) : cellState === "urgent" ? nudge(color, behind) : cellState === "occupied" ? nudge(root._toward(text(palette.barText), behind[0], 0.3), behind) : empty(behind), false, false, behind);
    const back = over(box.fill, behind);
    return root._makeCell(box.fill, box.stroke, box.indicator, box.onFill ? text(box.icon) : onBar(box.icon, back), false, box.onFill, back);
  }

  // What of a cell's box takes the bar's gradient (cell): filled on hover
  // its fill; in a merged run that draws its box, none; else its drawn
  // traits' `gradientPart`
  function _cellGradient(look, state, result) {
    if (result.showsHover)
      return root._part("fill", 1);
    if (state.group && BarLook.cellTraits(look, state.solid).groupCell)
      return null;
    return root._cellDrawn(look, state).gradientPart;
  }

  // What a value widget with "Colour the text by state" (its display
  // `appearance`) draws its text, its icon and its graphics in, { text,
  // icon, graphic }, given `colors` (colors()), its `stateColor` and
  // whether it `hasState` now: the state's color read where each sits
  // (content()), each where it doesn't sit on a fill it must read on
  // (`textOnFill`, `iconOnFill`: those keep theirs). The icon of a split
  // bar's icon part, on the state's own fill, never takes it.
  function stateContent(colors, appearance, stateColor, hasState) {
    if (!appearance?.colorText || !hasState)
      return {
        "text": colors.text,
        "icon": colors.icon,
        "graphic": colors.graphic
      };
    const text = colors.textOnFill ? colors.text : root.content(colors, stateColor, "text");
    const icon = colors.iconOnFill ? colors.icon : root.content(colors, stateColor, "icon");
    return {
      "text": text,
      "icon": icon,
      "graphic": colors.iconOnFill ? colors.graphic : root._graphic(colors.iconBack, icon, text)
    };
  }

  // A color of a widget's own on its `part` ("text" | "icon" | "mark" |
  // "headText"), read where that part sits (`colors`, colors()): to
  // textContrast for text (iconContrast for an icon or a mark), dimmed
  // where the widget is muted and pressed where it is. The bar's text
  // color itself is left as it is.
  function content(colors, color, part) {
    const text = part === "text";
    const backs = text ? colors.textBack : colors.iconBack;
    return root._read(colors, backs, color, text || part === "headText" ? root.textContrast : root.iconContrast, text ? colors.textOwnFill : colors.iconOwnFill);
  }

  // `color` taken opaque
  function _opaque(color) {
    return Qt.alpha(color, 1);
  }

  // `color` at `alpha` of its own opacity: a clear color (a widget with no
  // color of its own, Workspaces' box with its background off) stays
  // clear, where Qt.alpha would make it black at that opacity
  function faded(color, alpha) {
    const c = Qt.color(color);
    return Qt.alpha(c, c.a * alpha);
  }

  // `preferred` where it reads on `background` (WCAG contrast at least
  // 4.5), else whichever of it, the `alternates` (colors) and black and
  // white contrasts with it most (`preferred` on a tie)
  function readableOn(background, preferred, alternates) {
    if (Utils.contrast(background, preferred) >= 4.5)
      return preferred;
    const candidates = [preferred].concat(alternates ?? [], ["#000000", "#FFFFFF"]);
    return candidates.reduce((best, c) => Utils.contrast(background, c) > Utils.contrast(background, best) ? c : best);
  }

  // What reads on a fill the widget or run paints (`background`):
  // `preferred` or, where it doesn't read, the palette's foreground or
  // background, or black or white (readableOn). On a clear fill (a widget
  // with no color of its own) the text is on the bar: `preferred`.
  function _readable(palette, background, preferred) {
    if (Qt.color(background).a === 0)
      return preferred;
    return root.readableOn(background, preferred, [palette.barText, palette.background]);
  }

  function _part(part, alpha) {
    return {
      "part": part,
      "alpha": alpha
    };
  }

  function _makeCell(fill, stroke, indicator, content, showsHover, onFill, back) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "content": content,
      "showsHover": showsHover,
      "onFill": onFill,
      "back": back,
      "hover": "transparent"
    };
  }

  function _make(fill, stroke, indicator, text, icon, iconFill, textOnFill, textBack, iconBack, iconOnFill) {
    return {
      "fill": fill,
      "stroke": stroke,
      "indicator": indicator,
      "text": text,
      "icon": icon,
      "iconFill": iconFill,
      "textOnFill": textOnFill,
      "textBack": textBack,
      "iconBack": iconBack,
      "iconOnFill": iconOnFill,
      "level": "transparent",
      "accent": "transparent"
    };
  }
}
