pragma Singleton
import QtQuick

import qs.services.core
import qs.components.methods

// Reader for the Bars section and the bar look helpers: derived layout
// values (enrichBarConfig), widget colors, look groups and autoColor fields.
QtObject {
  // Adds derived orientation flags to a bar entry from the Bars section
  // (whose keys are always filled in from the schema defaults). Laid out
  // with the compositor's outer gaps (`gapsOut`: per edge name,
  // CompositorManager's) and the gaps an Automatic float gap keeps
  // (`floatGaps`: ScreenEdgeManager.floatGaps), which a floating bar's
  // islands keep from the screen edges as windows do.
  function enrichBarConfig(barConfig, gapsOut, floatGaps) {
    const loc = ScreenEdge.fromConfig(barConfig.location);
    // Its widget style, accents and shadow: its own style's, each key it
    // leaves null the Bars section's
    const look = BarsConfig.lookOf(barConfig);
    // The bar is sized by its widgets, never the other way round, so no
    // setting can leave them cut off
    const thickness = barConfig.thickness;
    // How much bigger than a 26 px bar it is: what's inside it scales so
    const scale = thickness / BarsConfig.referenceThickness;
    const edgePadding = barConfig.edgePadding;
    // What it draws as: its surface (one bar, a pill per group, none) and
    // whether that floats. With no surface it doesn't float.
    const kind = BarsConfig.kindOf(barConfig);
    const pills = kind === "pills";
    const solid = kind === "solid";
    // Floating bars are islands held off the edge: one along the bar, or
    // one per group of widgets
    const island = kind === "floating" || kind === "floatingPills";
    // Every bar but a solid one sits inside the screen border
    const insideBorder = !solid && Appearance.screenBorder;
    // What covers the bar's own pixels: the outer edge of a bar inside the
    // border lies on the border's stroke.
    const outerCover = insideBorder ? Appearance.borderWidth : 0;
    // Across: a full bar's extent, where its widgets start and how deep
    // its pills reach (BarEnds.crossGeometry: pills and solid alike; an
    // island's are its own, below)
    const cross = BarEnds.crossGeometry(kind, thickness, edgePadding, BarsConfig.endsOptions({}, {}));
    // A pill covers the screen border's stroke where it joins it
    const overlap = Appearance.screenBorder ? Appearance.borderWidth : 0;
    // A pill's free ends sit the padding and its stroke out from its
    // widgets, as its far side does
    const pillGap = edgePadding + Appearance.borderWidth;
    // Laid out like a tiled window: an island sits its float gap in from
    // the border's stroke (or the bare screen edge), across the bar and
    // from both its ends (Automatic, -1: the compositor's gaps_out on its
    // edge, as windows keep, or the screen margin with no backend; the ends take the same, so a gaps_out differing per
    // side leaves them off the windows' edges), and holds the widgets and
    // their padding inside a stroke. Windows keep gaps_out from it, as from
    // a screen edge: gaps_in is only between windows.
    const edge = ScreenEdge.name(loc);
    const floatingGapAuto = barConfig.floatingGap === null;
    const floatingGap = floatingGapAuto ? floatGaps[edge] ?? 0 : barConfig.floatingGap;
    const islandStart = outerCover + floatingGap;
    const islandDepth = Appearance.borderWidth + edgePadding + thickness + edgePadding + Appearance.borderWidth;
    const borderShadowed = solid && Appearance.screenBorder && barConfig.reserveSpace;
    // Shapes and grouping are for widgets drawn on a background
    const boxed = BarsConfig.boxedStyles.includes(look.widgetStyle);
    const grouping = boxed ? look.widgetGrouping : "separate";
    // Between the widgets within a section: a powerline's touch, and
    // dividers drawn between them take their own room and margins
    const groupSpacing = grouping === "powerline" ? 0 : look.separatorStyle !== "none" ? BarLayout.dividerGap(look.separatorStyle, look.separatorThickness, thickness, look.separatorGap) : barConfig.widgetGap;

    const vertical = loc === ScreenEdge.Left || loc === ScreenEdge.Right;
    const screen = General.outputs.find(s => s.name === barConfig.monitor) ?? null;
    const bar = {
      "id": barConfig.id,
      // The config entry's id: a bar on every monitor has one per screen
      "sourceId": barConfig.sourceId ?? barConfig.id,
      "enabled": barConfig.enabled,
      "monitor": barConfig.monitor,
      // A pill bar is as thick as its pills, so the padding always fits
      // and nothing is left between them and the windows
      "extent": island ? islandStart + islandDepth : cross.extent,
      "thickness": thickness,
      "edgePadding": edgePadding,
      // How far the widgets sit in from the bar's outer edge: past the
      // stroke and pill padding, or centred between whatever covers the bar
      "crossStart": island ? islandStart + Appearance.borderWidth + edgePadding : cross.crossStart,
      // solid, pills, transparent (no surface), floating, floatingPills
      "kind": kind,
      "solid": solid,
      "pills": pills,
      "island": island,
      "islandPills": kind === "floatingPills",
      // Where islands start, in from the bar window's outer edge and both
      // its ends, and the gap from their widgets to their ends
      "islandStart": islandStart,
      "floatingGap": island ? floatingGap : 0,
      // Its floating gap is Automatic (the compositor's gaps_out)
      "floatingGapAuto": floatingGapAuto,
      "islandGap": Appearance.borderWidth + edgePadding,
      "insideBorder": insideBorder,
      // A solid bar's inner stroke is the border strip's; with the border
      // off it draws its own, on its innermost pixels
      "innerStroke": solid && !Appearance.screenBorder,
      "overlap": overlap,
      "pillGap": pillGap,
      "pillDepth": cross.pillDepth,
      "widgetGap": barConfig.widgetGap,
      "groupSpacing": groupSpacing,
      // Neighbouring groups closer than this share a pill (or an island)
      "joinGap": Math.max(barConfig.widgetGap, groupSpacing),
      // What's drawn inside the bar follows the bar, never the Widget
      // section (that's for panels, popouts and controls): its text, icons
      // and inner spacing scale with its thickness, as set at 26 px (its
      // text scale of Appearance's font size there)
      "innerPadding": Math.round(barConfig.innerPadding * scale),
      "innerGap": Math.round(barConfig.innerGap * scale),
      "fontSize": Math.round(Appearance.baseFontSize * scale * look.textScale / 100),
      // Widget chips only, else the interior radius: pills and fillets keep
      // Appearance's, to meet the border
      "radius": look.widgetRadius ?? Widget.radius,
      // How widgets show their colors (see widgetColors); the color
      // names stay unresolved
      "widgetStyle": look.widgetStyle,
      // Its widgets are boxes (filled, tinted, outline), not bare on the bar
      "widgetBoxed": boxed,
      "tintOpacity": look.tintOpacity / 100,
      "outlineWidth": look.outlineWidth,
      "lineWidth": look.lineWidth,
      "lineSide": look.lineSide,
      "widgetTextColor": look.widgetTextColor,
      "widgetShape": boxed ? look.widgetShape : "rounded",
      "widgetEnds": look.widgetEnds,
      "widgetGrouping": grouping,
      "groupColor": look.groupColor,
      // A powerline's widgets touch, leaving no gap to divide
      "separatorStyle": grouping === "powerline" ? "none" : look.separatorStyle,
      "separatorColor": look.separatorColor,
      "separatorThickness": look.separatorThickness,
      "accentLine": look.accentLine,
      "accentLineColor": look.accentLineColor,
      "accentLineFade": look.accentLineFade,
      "accentLineWidth": look.accentLineWidth,
      // Cast by what the bar paints: a transparent one paints nothing. A
      // solid bar reserving its edge under the border leaves it to the
      // border, whose stroke is its inner edge (RoundedBorders)
      "shadow": kind !== "transparent" && !borderShadowed && look.shadow,
      "shadowColor": look.shadowColor,
      "shadowSize": look.shadowSize,
      // How far past the bar a shadow reaches (its blur and offset), which
      // the bar window takes on its inner side
      "shadowReach": kind !== "transparent" && !borderShadowed && look.shadow ? Math.ceil(look.shadowSize * 1.25) : 0,
      "lockCenter": barConfig.lockCenter,
      // As long as its widgets (at `align`: start, center, end), or the
      // whole edge
      "fit": barConfig.length === "fit",
      "align": barConfig.align,
      // never, always, whenCovered; what shows a hidden bar, and how long
      "autoHide": barConfig.autoHide,
      "revealOnWorkspace": barConfig.revealOnWorkspace,
      "revealOnActivity": barConfig.revealOnActivity,
      "revealFor": barConfig.revealFor,
      "timing": barConfig.timing,
      "trigger": barConfig.trigger,
      "location": loc,
      "reserveSpace": barConfig.reserveSpace,
      // Each Auto color picked for its place on this bar
      "widgets": BarsConfig.withAutoColors(barConfig.widgets, look.widgetStyle, grouping, look.groupColor),
      "vertical": vertical,
      // Along its screen's shorter edge: of two bars of a kind meeting at a
      // corner, it takes the corner (BarEnds)
      "shortEdge": screen ? BarEnds.onShortEdge(vertical, screen.width, screen.height) : vertical,
      "left": loc === ScreenEdge.Left,
      "right": loc === ScreenEdge.Right,
      "top": loc === ScreenEdge.Top,
      "bottom": loc === ScreenEdge.Bottom
    };
    // How much less than its extent it reserves alone on its edge
    // (reserveTrim). Where it lies among the other bars on its edge, what
    // it reserves there and what its ends meet depend on the other bars on
    // its screen: ScreenEdgeManager.bars adds them (BarEnds.withEnds).
    bar.trim = BarsConfig.reserveTrim(bar, gapsOut[edge] ?? 0);
    return bar;
  }

  // What a bar draws as, from its surface and floating: solid, pills,
  // transparent (no surface: a bar with none never floats), floating or
  // floatingPills
  function kindOf(barConfig) {
    if (barConfig.surface === "none")
      return "transparent";
    if (barConfig.surface === "pills")
      return barConfig.floating ? "floatingPills" : "pills";
    return barConfig.floating ? "floating" : "solid";
  }

  // A bar window's layer namespace, whose rule's `order` decides where
  // Hyprland arranges it (render.LayerRulesLua): by its kind
  // (solid, outside the border; pills; transparent; floating: bars and
  // pills held off the edge) and, for a bar along its screen's longer
  // edge, a -long one arranged after the shorter edge's bar of that kind
  // (BarEnds)
  function layerNamespace(barConfig) {
    const kind = barConfig.solid ? "axiom-bar" : barConfig.island ? "axiom-bar-floating" : barConfig.kind === "transparent" ? "axiom-bar-transparent" : "axiom-bar-pill";
    return barConfig.shortEdge ? kind : kind + "-long";
  }

  // BarEnds' options, from Appearance, the compositor's gaps_out and the
  // gaps an Automatic float gap keeps (enrichBarConfig)
  function endsOptions(gapsOut, floatGaps) {
    return {
      "border": Appearance.screenBorder,
      "borderWidth": Appearance.borderWidth,
      "margin": Appearance.screenMargin,
      "gapsOut": gapsOut,
      "floatGaps": floatGaps
    };
  }

  // What a bar widget draws in on its bar ({ fill, stroke, indicator,
  // text, icon }, see BarWidgetStyle): `accent` is its color for its state,
  // `foregroundName` the text color it's configured with
  function widgetColors(barConfig, accent, foregroundName) {
    return BarWidgetStyle.colors(BarsConfig._widgetStyle(barConfig, barConfig.widgetGrouping === "merged"), accent, Theme.resolveColor(foregroundName));
  }

  // What a cell inside a widget (a workspace) draws in on its bar ({ fill,
  // stroke, indicator, content }, see BarWidgetStyle.cell): `color` is its
  // state color, `own` what reads on it filled, `state` active/occupied/empty
  function cellColors(barConfig, color, own, state) {
    return BarWidgetStyle.cell(BarsConfig._widgetStyle(barConfig, false), color, own, state);
  }

  // The corners of a Workspaces cell `cell` thick, inset by `inset` in its
  // widget: a pill for capsule widgets, else the widgets' radius less the
  // inset
  function cellRadius(barConfig, cell, inset) {
    return barConfig.widgetShape === "capsule" ? cell / 2 : Math.max(0, barConfig.radius - inset);
  }

  // A Workspaces cell's box while hovered: its `hoverColor`, or for Auto
  // (empty) the theme's highlight
  function cellHoverColor(properties) {
    return properties?.hoverColor ? Theme.resolveColor(properties.hoverColor) : Theme.backgroundHighlight;
  }

  // What a merged run of widgets draws its shared background in
  function groupColors(barConfig) {
    const group = Theme.resolveColor(barConfig.groupColor);
    return BarWidgetStyle.colors(BarsConfig._widgetStyle(barConfig, false), group, BarWidgetStyle.readableOn(group, Theme.foreground));
  }

  // A bar's widgets (by section) with each Auto color field (`x-autoColor`,
  // left empty) set to the color BarAutoColors picks for it among its shown
  // neighbours, seen against the bar or, filled and merged, the run
  function withAutoColors(widgets, widgetStyle, grouping, groupColor) {
    const shown = [].concat(...BarsConfig.sectionNames.map(section => (widgets?.[section] ?? []).map((widget, index) => ({
            "section": section,
            "index": index,
            "widget": widget
          })))).filter(entry => entry.widget.visible !== false);
    const fields = shown.map(entry => {
      const roles = BarsConfig.autoColorFields[entry.widget.type] ?? {};
      const properties = entry.widget.properties ?? {};
      return {
        "roles": roles,
        "set": Object.keys(roles).filter(key => properties[key]).reduce((set, key) => {
          set[key] = Theme.resolveColor(properties[key]);
          return set;
        }, {})
      };
    });
    const filledRun = widgetStyle === "filled" && grouping === "merged";
    const named = name => ({
          "name": name,
          "color": Theme.resolveColor(name)
        });
    const picks = BarAutoColors.assign(fields, {
      "accents": Theme.baseColorNames.slice(8).map(named),
      "neutrals": Theme.baseColorNames.slice(1, 5).map(named),
      "warning": named("warning"),
      "critical": named("error"),
      "backdrop": filledRun ? Theme.resolveColor(groupColor) : Theme.background,
      // A fill need only show on the bar; otherwise the color is text or a stroke
      "minContrast": widgetStyle === "filled" && !filledRun ? 1.3 : 3
    });
    const result = Object.assign({}, widgets);
    shown.forEach((entry, n) => {
      if (Object.keys(picks[n]).length === 0)
        return;
      if (result[entry.section] === widgets[entry.section])
        result[entry.section] = widgets[entry.section].slice();
      result[entry.section][entry.index] = Object.assign({}, entry.widget, {
        "properties": Object.assign({}, entry.widget.properties, picks[n])
      });
    });
    return result;
  }

  // The thickness a bar's inner sizes (text scale, inner padding and gap)
  // are set at: they scale with the bar's thickness from there
  readonly property int referenceThickness: 26

  // The bar's sections, start to end
  readonly property var sectionNames: ["left", "center", "right"]
  // Each widget type's Auto color fields: { type: { key: role } }
  readonly property var autoColorFields: (ConfigManager.configSchema?.definitions?.BarWidget?.oneOf ?? []).reduce((result, refObj) => {
    const def = ConfigManager.configSchema.definitions[refObj.$ref.replace("#/definitions/", "")];
    const properties = def?.properties?.properties?.properties ?? {};
    result[def?.properties?.type?.const] = Object.keys(properties).filter(key => properties[key]["x-autoColor"]).reduce((roles, key) => {
      roles[key] = properties[key]["x-autoColor"];
      return roles;
    }, {});
    return result;
  }, {})

  // BarWidgetStyle's `style` for a bar, its colors resolved
  function _widgetStyle(barConfig, merged) {
    return {
      "fill": barConfig.widgetStyle,
      "barText": Theme.foreground,
      "override": barConfig.widgetTextColor ? Theme.resolveColor(barConfig.widgetTextColor) : null,
      "tint": barConfig.tintOpacity,
      "group": merged ? Theme.resolveColor(barConfig.groupColor) : null
    };
  }

  // The color of a shadow: `shadowColor` as a bar's look or the BarStyle
  // section has it. Automatic is the accent.
  function shadowBaseColor(look) {
    return Qt.color(look.shadowColor ? Theme.resolveColor(look.shadowColor) : Theme.accent);
  }

  // What a shadow is drawn in (shadowBaseColor). While surfaces blur, it
  // stays under Hyprland's blur threshold (Appearance.shadowAlphaMax), so
  // the blur doesn't spread into it.
  // Premultiplied, as MultiEffect blends its shadowColor: a color made
  // clearer by its alpha alone keeps its light (a glow capped to 0 still
  // drew in full, and SwayFX blurred it again on every redraw nearby).
  function shadowColor(look) {
    const color = shadowBaseColor(look);
    const a = Math.min(color.a, Appearance.shadowAlphaMax);
    return Qt.rgba(color.r * a, color.g * a, color.b * a, a);
  }

  // How much less than its extent a bar reserves, given Hyprland's
  // gaps_out on its edge. A transparent bar has no inner edge to see:
  // windows start where it would be, so the gap from the widgets to them
  // (padding + gaps_out, taken off here) matches the gap to the screen
  // edge. An inner accent line gives it one, on its innermost pixels:
  // windows keep gaps_out from it, as from a solid bar's stroke or a
  // floating bar's islands.
  function reserveTrim(barConfig, gapsOut) {
    if (barConfig.kind === "transparent" && barConfig.accentLine !== "inner")
      return gapsOut;
    return 0;
  }

  // How much further than half a connector gap past a transparent bar's
  // inner edge a box detached from it (a bar popout, a floating edge menu)
  // sits, so it starts in line with the windows: `windowsPast` is how far
  // past that edge they start (where its edge's bars and menus reserve to,
  // gaps_out on: at the bar's inner edge alone, or past an inner accent
  // line gaps_out out, reserveTrim). With bars inside it (not
  // `facesWindows`, BarEnds.placeStack), that's past them all: the box
  // clears the whole stack, never covering a bar. Negative when they
  // start nearer than half a connector gap: its attach edge moves in.
  function detachedPush(barConfig, windowsPast, connectorGap) {
    if (barConfig.kind !== "transparent")
      return 0;
    return windowsPast - connectorGap / 2;
  }

  // (The exclusive zone a bar sets is BarEnds.placeStack's `zone`: it
  // depends on the bars beside it on its edge.)

  // The widget styles that draw each widget on a box of its own: only they
  // have shapes and grouping
  readonly property var boxedStyles: ["filled", "tinted", "outline"]

  // A bar's look: its `style` (a BarStyle) with every key it leaves null
  // (inherit) taken from the Bars section's (`section`, BarStyle.values
  // when left out), its shadow as flat shadow / shadowColor / shadowSize,
  // and the bar's own fields beside them. widgetRadius stays null where
  // both leave it (Widget's then).
  function lookOf(barConfig, section) {
    const base = section ?? BarStyle.values;
    const own = barConfig?.style ?? {};
    const look = Object.assign({}, barConfig);
    for (const key in base) {
      if (key === "shadow")
        continue;
      look[key] = own[key] ?? base[key];
    }
    const shadow = own.shadow ?? {};
    look.shadow = shadow.enabled ?? base.shadow.enabled;
    look.shadowColor = shadow.color ?? base.shadow.color;
    look.shadowSize = shadow.size ?? base.shadow.size;
    return look;
  }

  // The look a bar's widgets draw in, as `$bar.<key>` for their options'
  // `x-showIf`: lookOf's BarStyle keys, with grouping only for boxed styles
  // (as enrichBarConfig)
  function lookContext(barConfig) {
    const look = BarsConfig.lookOf(barConfig ?? {});
    if (!BarsConfig.boxedStyles.includes(look.widgetStyle))
      look.widgetGrouping = "separate";
    return Object.keys(BarStyle.values).reduce((context, key) => {
      context["$bar." + key] = look[key];
      return context;
    }, {});
  }

  // The bars as saved (Bars.items): no previews, unexpanded
  readonly property var savedBars: ConfigManager.config.Bars.items

  // Each bar as one entry per screen it's on (its `screen`, a
  // ScreenTarget): the primary monitor, every monitor, or those named
  // (the primary monitor when none of them is connected). A bar on more
  // than one screen gets an id per screen (keying its BarPanel), `sourceId`
  // its own; `monitor` is the screen's name.
  function expandBars(bars) {
    return [].concat(...bars.map(bar => {
      const screens = General.screensFor(bar.screen);
      if (screens.length <= 1 || bar.screen.mode === "primary")
        return [Object.assign({}, bar, {
            "monitor": screens[0]?.name ?? ""
          })];
      return screens.map(screen => Object.assign({}, bar, {
          "id": `${bar.id}@${screen.name}`,
          "sourceId": bar.id,
          "monitor": screen.name
        }));
    }));
  }

  // A widget's `layout` overrides (priority, minSize, maxSize), for the bar
  // editor's inspector
  readonly property var widgetLayoutSchema: ConfigManager.configSchema.definitions.WidgetLayout
  // A bar's own fields in groups (`x-group`), for the bar editor (its
  // style is edited apart: styleGroups)
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.Bar, ["widgets", "style"])
  // The BarStyle fields in groups, for the bar editor's style (a bar's,
  // inheriting, or the Bars section's)
  readonly property var styleGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.BarStyle, [])

  readonly property var availableWidgetTypes: {
    const oneOf = ConfigManager.configSchema?.definitions?.BarWidget?.oneOf || [];
    return oneOf.map(refObj => {
      const refName = refObj.$ref.replace("#/definitions/", "");
      const def = ConfigManager.configSchema.definitions[refName];
      if (!def)
        return null;
      return {
        "type": def.properties?.type?.const,
        "label": def.properties?.type?.description || def.properties?.type?.const,
        // Material Symbols name (`x-icon`)
        "icon": def["x-icon"] ?? "widgets",
        // Its group in the widget library (`x-libraryGroup`)
        "group": def["x-libraryGroup"] ?? "",
        // More words the library finds it by (`x-keywords`)
        "keywords": def["x-keywords"] ?? [],
        // It shrinks when the bar is crowded, so takes a minSize and
        // maxSize (`x-elastic`)
        "elastic": def["x-elastic"] ?? false,
        // Its own priority when the bar is crowded (`x-priority`)
        "priority": def["x-priority"] ?? 0,
        "propertiesSchema": def.properties?.properties?.properties || null,
        // Its options shown first, in order (their `x-order`)
        "propertiesOrder": def.properties?.properties?.["x-order"] ?? [],
        // Where its feature is set (`x-link`), shown in the widget
        // inspector; undefined for none
        "link": def["x-link"]
      };
    }).filter(t => t !== null);
  }
  // A widget type's own priority when its bar is crowded (`x-priority`),
  // which a widget's `layout.priority` overrides
  function defaultPriority(type) {
    return BarsConfig.availableWidgetTypes.find(t => t.type === type)?.priority ?? 0;
  }
  // What the bar editor's library offers: the widget types, the custom
  // widgets one by one (keyed "CustomWidget:<id>",
  // CustomWidgetsConfig.splitKey) rather than the CustomWidget type
  readonly property var libraryWidgetTypes: availableWidgetTypes.filter(t => t.type !== "CustomWidget").concat(CustomWidgetsConfig.libraryEntries(availableWidgetTypes.find(t => t.type === "CustomWidget") ?? null))
}
