pragma Singleton
import QtQuick

// A bar's entry from the Bars section with its derived layout, look and
// palette (`enrich`: what BarsConfig.enrichBarConfig hands out), pure: the
// shell's values it reads come in as `env`, so tests run the real path.
// `env`: { barStyle (the Bars section's style), radius (Appearance's),
// widgetRadius (Widget.radius), baseFontSize, borderWidth, screenBorder,
// screenMargin, resolve (a color name to a color), foreground, background,
// outputs (the screens: name, width, height), autoColorFields
// (BarsConfig's), baseColorNames (Theme's), redForGains (Markets' Red for gains,
// which swaps the rise and fall roles) }.
QtObject {
  id: root

  // Adds derived orientation flags to a bar entry from the Bars section
  // (whose keys are always filled in from the schema defaults). Laid out
  // with the compositor's outer gaps (`gapsOut`: per edge name,
  // CompositorManager's) and the gaps an Automatic floating gap keeps
  // (`floatGaps`: ScreenEdgeManager.floatGaps), which a floating bar's
  // islands keep from the screen edges as windows do.
  function enrich(barConfig, gapsOut, floatGaps, env) {
    const loc = ScreenEdge.fromConfig(barConfig.location);
    // The bar is sized by its widgets, never the other way round, so no
    // setting can leave them cut off
    const thickness = barConfig.thickness;
    // How much bigger than a 26 px bar it is: what's inside it scales so
    const scale = thickness / root.referenceThickness;
    const edgePadding = barConfig.edgePadding;
    const innerPadding = Math.round(barConfig.innerPadding * scale);
    const innerGap = Math.round(barConfig.innerGap * scale);
    const iconGap = innerGap * 1.5;
    // Its widget style, accents and shadow resolved (BarLook): its own
    // style's, each key it leaves null the Bars section's
    const look = BarLook.resolve(env.barStyle, barConfig.style ?? {}, {
      "thickness": thickness,
      "innerPadding": innerPadding,
      "innerGap": innerGap,
      "radius": env.widgetRadius,
      "far": loc === ScreenEdge.Right || loc === ScreenEdge.Bottom
    });
    // What it draws as: its surface (one bar, a pill per group, none) and
    // whether that floats. With no surface it doesn't float.
    const kind = root.kindOf(barConfig);
    const pills = kind === "pills";
    const solid = kind === "solid";
    // Floating bars are islands held off the edge: one along the bar, or
    // one per group of widgets
    const island = kind === "floating" || kind === "floatingPills";
    // Every bar but a solid one sits inside the screen border
    const insideBorder = !solid && env.screenBorder;
    // What covers the bar's own pixels: the outer edge of a bar inside the
    // border lies on the border's stroke.
    const outerCover = insideBorder ? env.borderWidth : 0;
    // Across: a full bar's extent, where its widgets start and how deep
    // its pills reach (BarEnds.crossGeometry: pills and solid alike; an
    // island's are its own, below)
    const cross = BarEnds.crossGeometry(kind, thickness, edgePadding, root.endsOptions({}, {}, env));
    // A pill covers the screen border's stroke where it joins it
    const overlap = env.screenBorder ? env.borderWidth : 0;
    // A pill's free ends sit the padding and its stroke out from its
    // widgets, as its far side does
    const pillGap = edgePadding + env.borderWidth;
    // Laid out like a tiled window: an island sits its floating gap in
    // from the border's stroke (or the bare screen edge), across the bar
    // and from both its ends (Automatic, null: the compositor's gaps_out on
    // its edge, as windows keep, or the screen margin with no backend; the
    // ends take the same, so a gaps_out differing per side leaves them off
    // the windows' edges), and holds the widgets and
    // their padding inside a stroke. Windows keep gaps_out from it, as from
    // a screen edge: gaps_in is only between windows.
    const edge = ScreenEdge.name(loc);
    const floatingGapAuto = barConfig.floatingGap === null;
    const floatingGap = floatingGapAuto ? floatGaps[edge] ?? 0 : barConfig.floatingGap;
    const islandStart = outerCover + floatingGap;
    const islandDepth = env.borderWidth + edgePadding + thickness + edgePadding + env.borderWidth;
    // An auto-hiding bar reserves nothing unless pinned (ScreenEdgeManager
    // sets `pinned`; BarEnds zones it by reserveSpace || pinned)
    const autoHiding = barConfig.autoHide !== "never";
    const reserves = barConfig.reserveSpace && !autoHiding;
    const borderShadowed = solid && env.screenBorder && reserves;
    // Between the widgets within a section: a powerline's touch, and
    // dividers drawn between them take their own room and margins
    const separators = look.separators;
    const groupSpacing = look.grouping === "powerline" ? 0 : separators.style !== "none" ? BarLayout.dividerGap(separators.style, separators.thickness, thickness, separators.gap) : barConfig.widgetGap;

    const vertical = loc === ScreenEdge.Left || loc === ScreenEdge.Right;
    const screen = env.outputs.find(s => s.name === barConfig.monitor) ?? null;
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
      // How far the widgets sit in from the bar's outer edge: an island's
      // past its gap, stroke and padding, else BarEnds.crossGeometry's
      // (centred in a solid or pill bar, past the padding with no surface)
      "crossStart": island ? islandStart + env.borderWidth + edgePadding : cross.crossStart,
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
      "islandGap": env.borderWidth + edgePadding,
      "insideBorder": insideBorder,
      // A solid bar's inner stroke is the border strip's; with the border
      // off it draws its own, on its innermost pixels
      "innerStroke": solid && !env.screenBorder,
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
      "innerPadding": innerPadding,
      "innerGap": innerGap,
      // The gap between an icon and its label (6 px at the default inner spacing of 4)
      "iconGap": iconGap,
      "fontSize": Math.round(env.baseFontSize * scale * look.textScale / 100),
      // Widget chips only, else the interior radius: pills and fillets keep
      // Appearance's, to meet the border
      "radius": look.radius,
      // How its widgets are drawn: their style, shapes, runs, split, the
      // gradient, separators and accent line (BarLook.resolve)
      "look": look,
      // The look's colors, resolved (BarWidgetStyle.palette)
      "palette": BarWidgetStyle.palette(look, env.resolve, env.foreground, env.background),
      // The gap a split widget keeps between its parts
      // (BarShapes.splitRoom), -1 on other styles
      "splitRoom": look.split ? look.split.room : -1,
      // Cast by what the bar paints: a transparent one paints nothing. A
      // solid bar reserving its edge under the border leaves it to the
      // border, whose stroke is its inner edge (RoundedBorders)
      "shadow": kind !== "transparent" && !borderShadowed && look.values.shadow,
      "shadowColor": look.values.shadowColor,
      "shadowSize": look.values.shadowSize,
      // How far past the bar a shadow reaches (its blur and offset), which
      // the bar window takes on its inner side
      "shadowReach": kind !== "transparent" && !borderShadowed && look.values.shadow ? Math.ceil(look.values.shadowSize * 1.25) : 0,
      "lockCenter": barConfig.lockCenter,
      // never, always, whenCovered; what shows a hidden bar, and how long
      "autoHide": barConfig.autoHide,
      "autoHiding": autoHiding,
      // Pinned shown by the `bar` IPC toggle: it then reserves its space
      // (BarRevealManager; ScreenEdgeManager sets it)
      "pinned": false,
      "revealOnWorkspace": barConfig.revealOnWorkspace,
      "revealOnActivity": barConfig.revealOnActivity,
      "revealFor": barConfig.revealFor,
      "timing": barConfig.timing,
      "location": loc,
      // As configured: never for an auto-hiding bar (what its stack slot
      // and corners go by, so hiding, showing and pinning never move them)
      "reserveSpace": reserves,
      // Each Auto color picked for its place on this bar
      "widgets": root.withAutoColors(barConfig.widgets, look, env),
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
    bar.trim = root.reserveTrim(bar, gapsOut[edge] ?? 0);
    // The one fillet radius its flared tabs share (BarTabs.tabFillet):
    // within the gap between widgets and the room at its ends
    look.shape.tabFillet = BarTabs.tabFillet(bar.radius, thickness, look.shape.tabCorners, groupSpacing, BarEnds.tabEndRoom(bar, Object.assign(root.endsOptions(gapsOut, floatGaps, env), {
      "radius": env.radius
    })));
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

  // BarEnds' options, from the screen border and margin (`env`), the
  // compositor's gaps_out and the gaps an Automatic floating gap keeps
  // (enrich)
  function endsOptions(gapsOut, floatGaps, env) {
    return {
      "border": env.screenBorder,
      "borderWidth": env.borderWidth,
      "margin": env.screenMargin,
      "gapsOut": gapsOut,
      "floatGaps": floatGaps
    };
  }

  // How much less than its extent a bar reserves, given Hyprland's
  // gaps_out on its edge. A transparent bar has no inner edge to see:
  // windows start where it would be, so the gap from the widgets to them
  // (padding + gaps_out, taken off here) matches the gap to the screen
  // edge. An inner accent line gives it one, on its innermost pixels:
  // windows keep gaps_out from it, as from a solid bar's stroke or a
  // floating bar's islands.
  function reserveTrim(barConfig, gapsOut) {
    if (barConfig.kind === "transparent" && barConfig.look.accentLine?.side !== "inner")
      return gapsOut;
    return 0;
  }

  // A bar's widgets (by section) with each Auto color field (`x-autoColor`,
  // left empty) set to the color BarAutoColors picks for it among its shown
  // neighbours, seen against the bar or, filled and merged, the run
  // (`look`'s autoContrast trait, BarLook), and those fields' roles as the
  // widget's `autoColors` ({ key: { role, gradient } })
  function withAutoColors(widgets, look, env) {
    const shown = [].concat(...root.sectionNames.map(section => (widgets?.[section] ?? []).map((widget, index) => ({
            "section": section,
            "index": index,
            "widget": widget
          })))).filter(entry => entry.widget.visible !== false);
    const fields = shown.map(entry => {
      const roles = env.autoColorFields[entry.widget.type] ?? {};
      const properties = entry.widget.properties ?? {};
      return {
        "roles": Object.keys(roles).reduce((byKey, key) => {
          byKey[key] = roles[key].role;
          return byKey;
        }, {}),
        "gradient": roles,
        "set": Object.keys(roles).filter(key => properties[key]).reduce((set, key) => {
          set[key] = env.resolve(properties[key]);
          return set;
        }, {})
      };
    });
    const seen = look.traits.autoContrast;
    const named = name => ({
          "name": name,
          "color": env.resolve(name)
        });
    const picks = BarAutoColors.assign(fields, {
      "accents": env.baseColorNames.slice(8).map(named),
      "neutrals": env.baseColorNames.slice(1, 5).map(named),
      "warning": named("warning"),
      "critical": named("error"),
      "rise": named(env.redForGains ? "error" : "success"),
      "fall": named(env.redForGains ? "success" : "error"),
      "backdrop": seen.onRun ? env.resolve(look.group.color) : env.background,
      // A fill need only show on the bar; otherwise the color is text or a stroke
      "minContrast": seen.minContrast
    });
    const result = Object.assign({}, widgets);
    shown.forEach((entry, n) => {
      if (Object.keys(picks[n]).length === 0)
        return;
      if (result[entry.section] === widgets[entry.section])
        result[entry.section] = widgets[entry.section].slice();
      result[entry.section][entry.index] = Object.assign({}, entry.widget, {
        "properties": Object.assign({}, entry.widget.properties, picks[n]),
        // Which of its fields are Auto ({ key: { role, gradient } }):
        // whether each gives way to the bar's gradient
        "autoColors": Object.keys(picks[n]).reduce((auto, key) => {
          auto[key] = {
            "role": fields[n].roles[key],
            "gradient": fields[n].gradient[key].gradient
          };
          return auto;
        }, {})
      });
    });
    return result;
  }

  // Each widget type's Auto color fields from the config schema (the
  // built config.schema.json): { type: { key: { role, gradient } } }: its
  // `x-autoColor` role, and whether it gives way to the bar's gradient
  // while Auto (an `accent` always, else `x-autoGradient`)
  function autoColorFields(schema) {
    return (schema?.definitions?.BarWidget?.oneOf ?? []).reduce((result, refObj) => {
      const def = schema.definitions[refObj.$ref.replace("#/definitions/", "")];
      const properties = def?.properties?.properties?.properties ?? {};
      result[def?.properties?.type?.const] = Object.keys(properties).filter(key => properties[key]["x-autoColor"]).reduce((roles, key) => {
        roles[key] = {
          "role": properties[key]["x-autoColor"],
          "gradient": properties[key]["x-autoColor"] === "accent" || properties[key]["x-autoGradient"] === true
        };
        return roles;
      }, {});
      return result;
    }, {});
  }

  // The thickness a bar's inner sizes (text scale, inner padding and gap)
  // are set at: they scale with the bar's thickness from there
  readonly property int referenceThickness: 26

  // The bar's sections, start to end
  readonly property var sectionNames: ["left", "center", "right"]
}
