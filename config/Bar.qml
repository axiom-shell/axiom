pragma Singleton
import QtQuick

import qs.services.core
import qs.components.methods

// Reader for the Bars section and the bar look helpers: derived layout
// values (enrichBarConfig), widget colors, look groups and autoColor fields.
QtObject {
  enum Location {
    Top,
    Bottom,
    Left,
    Right
  }
  // Adds derived orientation flags to a bar entry from the Bars section
  // (whose keys are always filled in from the schema defaults). Laid out
  // with the compositor's outer gaps (`gapsOut`: per edge name,
  // CompositorManager's),
  // which a floating bar's islands keep from the screen edges as windows
  // do (ScreenEdgeManager.bars).
  function enrichBarConfig(barConfig, gapsOut) {
    const loc = Bar.getLocationFromString(barConfig.location);
    // Its widget style, accents and shadow: its own style's, each key it
    // leaves null the Bars section's
    const look = Bar.lookOf(barConfig);
    // The bar is sized by its widgets, never the other way round, so no
    // setting can leave them cut off
    const widgetSize = barConfig.widgetSize;
    const padding = barConfig.padding;
    const background = barConfig.background ?? "solid";
    const pills = background === "pills";
    const solid = background === "solid";
    // Floating bars are islands held off the edge: one along the bar, or
    // one per group of widgets
    const island = background === "floating" || background === "floatingPills";
    // Every bar but a solid one sits inside the screen border
    const insideBorder = !solid && Appearance.screenBorder;
    // What covers the bar's own pixels: the outer edge of a bar inside the
    // border lies on the border's stroke, and a solid bar with the border
    // off draws its own stroke on its inner edge. A solid bar's border strip
    // only draws its stroke past the bar (RoundedBorders.frameColorFor).
    const outerCover = insideBorder ? Appearance.borderWidth : 0;
    const innerCover = solid && !Appearance.screenBorder ? Appearance.borderWidth : 0;
    // A solid bar reaches at least as far as the border strip laid over its
    // inner part (BarPanel.reservedZone), so no gap opens under the strip
    const minExtent = solid && Appearance.screenBorder ? Appearance.screenMargin - Appearance.borderWidth : 0;
    const plainExtent = Math.max(minExtent, outerCover + padding + widgetSize + padding + innerCover);
    // A pill covers the screen border's stroke where it joins it
    const overlap = Appearance.screenBorder ? Appearance.borderWidth : 0;
    // Padding past the border's stroke on the pill's outer side, so its
    // widgets sit the frame plus this in from the screen edge
    const pillPad = barConfig.pillPadding ?? 0;
    // How far a pill's widgets sit in from the bar's outer edge (and its
    // ends): past the border stroke, or with the border off, the screen
    // margin the frame would have taken, so they keep the same gap from the
    // bare screen edge
    const pillInset = overlap + (Appearance.screenBorder ? 0 : Appearance.screenMargin) + pillPad;
    // The widgets' gap to every edge they're seen against: the screen edge
    // (through the frame), and the pill's inner side and free ends (to the
    // outside of its stroke)
    const pillGap = Math.max(Appearance.borderWidth, Appearance.screenMargin + pillPad);
    // How far a pill reaches in from the bar's outer edge: the inset, its
    // widgets, and the gap to its far side
    const pillDepth = pillInset + widgetSize + pillGap;
    // Laid out like a tiled window: an island sits its float gap in from
    // the border's stroke (or the bare screen edge), across the bar and
    // from both its ends (Automatic, -1: Hyprland's gaps_out on its edge,
    // as windows keep; the ends take the same, so a gaps_out differing per
    // side leaves them off the windows' edges), and holds the widgets and
    // their padding inside a stroke. Windows keep gaps_out from it, as from
    // a screen edge: gaps_in is only between windows.
    const edge = Bar.edgeName(loc);
    const floatGap = barConfig.floatGap >= 0 ? barConfig.floatGap : gapsOut[edge] ?? 0;
    const islandStart = outerCover + floatGap;
    const islandDepth = Appearance.borderWidth + padding + widgetSize + padding + Appearance.borderWidth;
    const borderShadowed = solid && Appearance.screenBorder && barConfig.reserveSpace;
    // Shapes and grouping are for widgets drawn on a background
    const boxed = Bar.boxedStyles.includes(look.widgetStyle);
    const grouping = boxed ? look.widgetGrouping : "separate";

    const vertical = loc === Bar.Left || loc === Bar.Right;
    const screen = General.outputs.find(s => s.name === barConfig.monitor) ?? null;
    const bar = {
      "id": barConfig.id,
      // The config entry's id: a bar on every monitor has one per screen
      "sourceId": barConfig.sourceId ?? barConfig.id,
      "enabled": barConfig.enabled,
      "monitor": barConfig.monitor,
      // A pill bar is as thick as its pills, so the padding always fits
      // and nothing is left between them and the windows
      "extent": pills ? pillDepth : island ? islandStart + islandDepth : plainExtent,
      "widgetSize": widgetSize,
      "padding": padding,
      // How far the widgets sit in from the bar's outer edge: past the
      // stroke and pill padding, or centred between whatever covers the bar
      "crossStart": pills ? pillInset : island ? islandStart + Appearance.borderWidth + padding : outerCover + (plainExtent - outerCover - innerCover - widgetSize) / 2,
      "background": background,
      "solid": solid,
      "pills": pills,
      "island": island,
      "islandPills": background === "floatingPills",
      // Where islands start, in from the bar window's outer edge and both
      // its ends, and the gap from their widgets to their ends
      "islandStart": islandStart,
      "floatGap": island ? floatGap : 0,
      // Its float gap is Automatic (Hyprland's gaps_out)
      "floatGapAuto": barConfig.floatGap < 0,
      "islandGap": Appearance.borderWidth + padding,
      "insideBorder": insideBorder,
      // An inner stroke surfaces on its edge can join: a solid bar's
      "joinable": solid,
      // A solid bar's inner stroke is the border strip's; with the border
      // off it draws its own, on its innermost pixels
      "innerStroke": solid && !Appearance.screenBorder,
      "overlap": overlap,
      "pillInset": pillInset,
      "pillGap": pillGap,
      "pillMerge": barConfig.pillMerge ?? 0,
      "pillDepth": pillDepth,
      "spacing": barConfig.spacing,
      // Between the widgets within a section: a powerline's touch, and
      // dividers drawn between them take their own room and margins
      "groupSpacing": grouping === "powerline" ? 0 : look.separatorStyle !== "none" ? BarLayout.dividerGap(look.separatorStyle, look.separatorThickness, widgetSize, look.separatorGap) : barConfig.spacing,
      // What's drawn inside the bar follows the bar, never the Widget
      // section (that's for panels, popouts and controls)
      "widgetPadding": barConfig.widgetPadding,
      "widgetSpacing": barConfig.widgetSpacing,
      "fontSize": look.fontSize ?? Appearance.baseFontSize,
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
      "separatorGap": look.separatorGap,
      "accentLine": look.accentLine,
      "accentLineColor": look.accentLineColor,
      "accentLineFade": look.accentLineFade,
      "accentLineWidth": look.accentLineWidth,
      // Cast by what the bar paints: a transparent one paints nothing. A
      // solid bar reserving its edge under the border leaves it to the
      // border, whose stroke is its inner edge (RoundedBorders)
      "shadow": background !== "transparent" && !borderShadowed && look.shadow,
      "shadowColor": look.shadowColor,
      "shadowSize": look.shadowSize,
      // How far past the bar a shadow reaches (its blur and offset), which
      // the bar window takes on its inner side
      "shadowReach": background !== "transparent" && !borderShadowed && look.shadow ? Math.ceil(look.shadowSize * 1.25) : 0,
      "lockCenter": barConfig.lockCenter,
      "location": loc,
      "reserveSpace": barConfig.reserveSpace,
      // Each Auto color picked for its place on this bar
      "widgets": Bar.withAutoColors(barConfig.widgets, look.widgetStyle, grouping, look.groupColor),
      "vertical": vertical,
      // Along its screen's shorter edge: of two bars of a kind meeting at a
      // corner, it takes the corner (BarEnds)
      "shortEdge": screen ? BarEnds.onShortEdge(vertical, screen.width, screen.height) : vertical,
      "left": loc === Bar.Left,
      "right": loc === Bar.Right,
      "top": loc === Bar.Top,
      "bottom": loc === Bar.Bottom
    };
    // How much less than its extent it reserves (reserveTrim). What its
    // ends meet depends on the other bars on its screen: ScreenEdgeManager.bars
    // adds them (BarEnds.withEnds).
    bar.trim = Bar.reserveTrim(bar, gapsOut[edge] ?? 0);
    return bar;
  }

  // A bar window's layer namespace, whose rule's `order` decides where
  // Hyprland arranges it (HyprLua.layerRulesLua): by its kind
  // (solid, outside the border; pills; transparent; floating: bars and
  // pills held off the edge) and, for a bar along its screen's longer
  // edge, a -long one arranged after the shorter edge's bar of that kind
  // (BarEnds)
  function layerNamespace(barConfig) {
    const kind = barConfig.solid ? "axiom-bar" : barConfig.island ? "axiom-bar-floating" : barConfig.background === "transparent" ? "axiom-bar-transparent" : "axiom-bar-pill";
    return barConfig.shortEdge ? kind : kind + "-long";
  }

  // BarEnds' options, from Appearance and Hyprland's gaps_out
  function endsOptions(gapsOut) {
    return {
      "border": Appearance.screenBorder,
      "borderWidth": Appearance.borderWidth,
      "gapsOut": gapsOut
    };
  }

  // What a bar widget draws in on its bar ({ fill, stroke, indicator,
  // text, icon }, see BarWidgetStyle): `accent` is its color for its state,
  // `foregroundName` the text color it's configured with
  function widgetColors(barConfig, accent, foregroundName) {
    return BarWidgetStyle.colors(Bar._widgetStyle(barConfig, barConfig.widgetGrouping === "merged"), accent, Theme.resolveColor(foregroundName));
  }

  // What a cell inside a widget (a workspace) draws in on its bar ({ fill,
  // stroke, indicator, content }, see BarWidgetStyle.cell): `color` is its
  // state color, `own` what reads on it filled, `state` active/occupied/empty
  function cellColors(barConfig, color, own, state) {
    return BarWidgetStyle.cell(Bar._widgetStyle(barConfig, false), color, own, state);
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
    return BarWidgetStyle.colors(Bar._widgetStyle(barConfig, false), group, BarWidgetStyle.readableOn(group, Theme.foreground));
  }

  // A bar's widgets (by section) with each Auto color field (`x-autoColor`,
  // left empty) set to the color BarAutoColors picks for it among its shown
  // neighbours, seen against the bar or, filled and merged, the run
  function withAutoColors(widgets, widgetStyle, grouping, groupColor) {
    const shown = [].concat(...Bar.sectionNames.map(section => (widgets?.[section] ?? []).map((widget, index) => ({
            "section": section,
            "index": index,
            "widget": widget
          })))).filter(entry => entry.widget.visible !== false);
    const fields = shown.map(entry => {
      const roles = Bar.autoColorFields[entry.widget.type] ?? {};
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

  // The bar's sections, start to end
  readonly property var sectionNames: ["left", "leftCenter", "center", "rightCenter", "right"]
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
    if (barConfig.background === "transparent" && barConfig.accentLine !== "inner")
      return gapsOut;
    return 0;
  }

  // How much further than half a connector gap past a transparent bar's
  // inner edge a box detached from it (a bar popout, a floating edge menu)
  // sits, so it starts in line with the windows: at the bar's inner edge,
  // or past an inner accent line gaps_out out (reserveTrim). Negative when
  // they start nearer than half a connector gap: its attach edge moves in.
  function detachedPush(barConfig, gapsOut, connectorGap) {
    if (barConfig.background !== "transparent")
      return 0;
    return gapsOut - Bar.reserveTrim(barConfig, gapsOut) - connectorGap / 2;
  }

  // The exclusive zone a bar sets (BarPanel), given Hyprland's gaps_out on
  // its edge. On a bar inside the border Hyprland counts its -borderWidth
  // margin into the reserved space, so that much less is reserved in all.
  function reservedZone(barConfig, gapsOut) {
    if (!barConfig.reserveSpace)
      return 0;
    const trim = Bar.reserveTrim(barConfig, gapsOut);
    if (barConfig.insideBorder)
      return Math.max(0, barConfig.extent - trim);
    return Math.max(0, (Appearance.screenBorder ? barConfig.extent - Appearance.screenMargin + Appearance.borderWidth : barConfig.extent) - trim);
  }

  // The widget styles that draw each widget on a box of its own: only they
  // have shapes and grouping
  readonly property var boxedStyles: ["filled", "tinted", "outline"]

  // A bar's look: its `style` (a BarStyle) with every key it leaves null
  // (inherit) taken from the Bars section's (`section`, BarStyle.values
  // when left out), its shadow as flat shadow / shadowColor / shadowSize,
  // and the bar's own fields beside them. fontSize and widgetRadius stay
  // null where both leave them (Appearance's and Widget's then).
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
    const look = Bar.lookOf(barConfig ?? {});
    if (!Bar.boxedStyles.includes(look.widgetStyle))
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

  // A widget's `layout` overrides (size, minSize, priority), for the bar
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
        "propertiesSchema": def.properties?.properties?.properties || null,
        // Its options shown first, in order (their `x-order`)
        "propertiesOrder": def.properties?.properties?.["x-order"] ?? [],
        // Where its feature is set (`x-link`), shown in the widget
        // inspector; undefined for none
        "link": def["x-link"]
      };
    }).filter(t => t !== null);
  }
  // A Bar.Location as the edge names zones and Hyprland use: "top" |
  // "bottom" | "left" | "right"
  function edgeName(location) {
    return ["top", "bottom", "left", "right"][location];
  }
  // The Bar.Location an edge name stands for (edgeName's inverse)
  function locationOf(name) {
    return ["top", "bottom", "left", "right"].indexOf(name);
  }

  // The edge across the screen from a Bar.Location
  function oppositeOf(location) {
    return [Bar.Bottom, Bar.Top, Bar.Right, Bar.Left][location];
  }

  // The Bar.Location of an edge in config ("top" | "bottom" | "left" |
  // "right"), Top for anything else
  function getLocationFromString(locStr) {
    return Math.max(0, Bar.locationOf(locStr));
  }
}
