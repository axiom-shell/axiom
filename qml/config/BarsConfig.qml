pragma Singleton
import QtQuick

import qs.services.core
import qs.components.methods

// Reader for the Bars section and the bar look helpers: derived layout
// values (enrichBarConfig), widget colors, look groups and autoColor fields.
QtObject {
  id: root

  // Adds derived orientation flags to a bar entry from the Bars section
  // (whose keys are always filled in from the schema defaults), laid out
  // with the compositor's outer gaps (`gapsOut`: per edge name,
  // CompositorManager's) and the gaps an Automatic floating gap keeps
  // (`floatGaps`: ScreenEdgeManager.floatGaps). BarEnrich.enrich does it.
  function enrichBarConfig(barConfig, gapsOut, floatGaps) {
    return BarEnrich.enrich(barConfig, gapsOut, floatGaps, root.enrichEnv());
  }

  // What BarEnrich reads of the shell (its `env`)
  function enrichEnv() {
    return {
      "barStyle": BarStyle.values,
      "radius": Appearance.borderRadius,
      "widgetRadius": Widget.radius,
      "baseFontSize": Appearance.baseFontSize,
      "borderWidth": Appearance.borderWidth,
      "screenBorder": Appearance.screenBorder,
      "screenMargin": Appearance.screenMargin,
      "resolve": name => Theme.resolveColor(name),
      "foreground": Theme.foreground,
      "background": Theme.background,
      "outputs": General.outputs,
      "autoColorFields": root.autoColorFields,
      "baseColorNames": Theme.baseColorNames,
      "redForGains": MarketsConfig.redForGains
    };
  }

  // What a bar draws as, from its surface and floating: solid, pills,
  // transparent, floating or floatingPills (BarEnrich.kindOf)
  function kindOf(barConfig) {
    return BarEnrich.kindOf(barConfig);
  }

  // A bar window's layer namespace, whose rule's `order` decides where
  // Hyprland arranges it (render.LayerRulesLua): by its kind
  // (solid, outside the border; pills; floating: bars and pills held off
  // the edge; transparent) and, for a bar along its screen's longer
  // edge, a -long one arranged after the shorter edge's bar of that kind
  // (BarEnds)
  function layerNamespace(barConfig) {
    const kind = barConfig.solid ? "axiom-bar" : barConfig.island ? "axiom-bar-floating" : barConfig.kind === "transparent" ? "axiom-bar-transparent" : "axiom-bar-pill";
    return barConfig.shortEdge ? kind : kind + "-long";
  }

  // BarEnds' options, from Appearance, the compositor's gaps_out and the
  // gaps an Automatic floating gap keeps (BarEnrich.endsOptions)
  function endsOptions(gapsOut, floatGaps) {
    return BarEnrich.endsOptions(gapsOut, floatGaps, root.enrichEnv());
  }

  // What a bar widget draws in on its bar (BarWidgetStyle.widgetColors):
  // `foregroundName` is the text color it's configured with.
  function widgetColors(barConfig, accent, foregroundName, widget) {
    return BarWidgetStyle.widgetColors(barConfig, accent, Theme.resolveColor(foregroundName), widget);
  }

  // What a cell inside a widget (a workspace) draws in on its bar ({ fill,
  // stroke, indicator, content, showsHover }, see BarWidgetStyle.cell):
  // `color` is its state color, `own` what reads on it filled, `state`
  // active/occupied/urgent/empty, `cell` what of the cell its look depends
  // on (BarWidgetStyle.state's hovered, spot, under, auto, muted
  // and hover: where the middle of a cell whose color is Auto sits along
  // the bar, for the bar's gradient to take its place, `auto` saying it
  // gives way to it; `solid`: a filled
  // box whatever the bar's style, Workspaces' `solidBoxes`; and `onBar`:
  // drawn in its widget on the bar, not a popout, so in a merged run on a
  // merged bar)
  function cellColors(barConfig, color, own, state, cell) {
    const palette = barConfig.palette;
    return BarWidgetStyle.cell(barConfig.look, palette, BarWidgetStyle.state(palette, {
      "hovered": cell?.hovered,
      "spot": cell?.spot,
      "auto": cell?.auto === true,
      "solid": cell?.solid,
      "under": cell?.under,
      "muted": cell?.muted,
      "hover": cell?.hover,
      "group": cell?.onBar === true && barConfig.look.grouping === "merged"
    }), color, own, state);
  }

  // A Workspaces cell's colors (cellColors) by its state, in the widget's
  // `colors` ({ activeColor, occupiedColor, urgentColor, emptyColor,
  // textColor, solidBoxes }): urgent beats occupied, active beats both.
  // `cell`: cellColors' (hovered, spot; solid comes from `colors`)
  function workspaceCellColors(barConfig, colors, active, occupied, urgent, cell) {
    const state = active ? "active" : urgent ? "urgent" : occupied ? "occupied" : "empty";
    const color = {
      "active": colors.activeColor,
      "urgent": colors.urgentColor,
      "occupied": colors.occupiedColor,
      "empty": colors.emptyColor
    }[state];
    return BarsConfig.cellColors(barConfig, color, state === "empty" ? barConfig.palette.barText : colors.textColor, state, Object.assign({}, cell, {
      "solid": colors.solidBoxes === true
    }));
  }

  // The gap between Workspaces cells on `barConfig`'s bar for their
  // `spacing` option: none ("tight"), the bar's inner gap ("bar") or twice
  // it ("wide")
  function workspaceCellSpacing(barConfig, spacing) {
    return spacing === "tight" ? 0 : spacing === "wide" ? barConfig.innerGap * 2 : barConfig.innerGap;
  }

  // The corners of a Workspaces cell `cell` thick, inset by `inset` in its
  // widget: a pill for capsule widgets, else the widgets' radius less the
  // inset
  function cellRadius(barConfig, cell, inset) {
    return barConfig.look.shape.name === "capsule" ? cell / 2 : Math.max(0, barConfig.radius - inset);
  }

  // A Workspaces widget's colors from its options (`properties`), resolved:
  // { activeColor, occupiedColor, urgentColor, emptyColor, textColor,
  // hoverColor }, as workspaceCellColors takes them (hoverColor: a cell's
  // hover box, null for Auto: the palette's cellHover, BarWidgetStyle.cell)
  function workspaceColors(properties) {
    return {
      "activeColor": Theme.resolveColor(properties.activeColor),
      "occupiedColor": Theme.resolveColor(properties.occupiedColor),
      "urgentColor": Theme.resolveColor(properties.urgentColor),
      "emptyColor": Theme.resolveColor(properties.emptyColor),
      "textColor": Theme.resolveColor(properties.foregroundColor),
      "hoverColor": properties.hoverColor ? Theme.resolveColor(properties.hoverColor) : null
    };
  }

  // What a merged run of widgets draws its shared background in: with a
  // gradient on the bar, one strip of it (`spot`: the run's middle along
  // the bar, 0-1), else groupColor, an outline run's line
  // groupStrokeColor (it has no background of its own)
  function groupColors(barConfig, spot = -1) {
    return BarWidgetStyle.runColors(barConfig.look, barConfig.palette, spot);
  }

  // A bar's widgets with each Auto color field set to the color picked for
  // it (BarEnrich.withAutoColors)
  function withAutoColors(widgets, look) {
    return BarEnrich.withAutoColors(widgets, look, root.enrichEnv());
  }

  // The thickness a bar's inner sizes (text scale, inner padding and gap)
  // are set at: they scale with the bar's thickness from there
  readonly property int referenceThickness: BarEnrich.referenceThickness

  // The bar's sections, start to end
  readonly property var sectionNames: BarEnrich.sectionNames
  // Each widget type's Auto color fields: { type: { key: { role, gradient } } }: its
  // `x-autoColor` role, and whether it gives way to the bar's gradient
  // while Auto (an `accent` always, else `x-autoGradient`)
  readonly property var autoColorFields: BarEnrich.autoColorFields(ConfigManager.configSchema)

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

  // A bar's style values, flat: its `style` (a BarStyle) with every key
  // it leaves null (inherit) taken from the Bars section's (`section`,
  // BarStyle.values when left out; BarLook.merge), its shadow as flat
  // shadow / shadowColor / shadowSize, and the bar's own fields beside
  // them. widgetRadius stays null where both leave it (Widget's then).
  // For the bar editor's forms; what a bar draws is barConfig.look.
  function lookOf(barConfig, section) {
    return Object.assign({}, barConfig, BarLook.merge(section ?? BarStyle.values, barConfig?.style ?? {}));
  }

  // The look a bar's widgets draw in, as `$bar.<key>` for their options'
  // `x-showIf` (BarLook.context): its BarStyle values, with shape and
  // grouping as drawn
  function lookContext(barConfig) {
    return BarLook.context(BarLook.resolve(BarStyle.values, barConfig?.style ?? {}, null));
  }

  // The bars as saved (Bars.items): no previews, unexpanded
  readonly property var savedBars: ConfigManager.config.Bars.items

  // Each bar as one entry per screen it's on (its `screen`, a
  // ScreenTarget): the primary monitor, every monitor, or those named
  // (the primary monitor when none of them is connected). A bar whose
  // mode isn't primary (inherit included) gets an id per screen, even on
  // one (keying its BarPanel, so it depends only on its screen: a monitor
  // plugged in or out leaves the others' windows), `sourceId` its own;
  // `monitor` is the screen's name.
  function expandBars(bars) {
    return [].concat(...bars.map(bar => {
      const screens = General.screensFor(bar.screen);
      if (screens.length === 0 || bar.screen.mode === "primary")
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

  // The bar editor's tabs (its left panel's), by the groups (`x-group`
  // titles) of fieldGroups and styleGroups each shows: a Bar group no tab
  // names goes on the first
  readonly property var editorTabs: [
    {
      "label": I18n.tr("Layout"),
      "fields": ["Placement", "Size"],
      "styles": []
    },
    {
      "label": I18n.tr("Surface"),
      "fields": ["Surface"],
      "styles": []
    },
    {
      "label": I18n.tr("Style"),
      "fields": [],
      "styles": ["Look", "Size", "Colors", "Accents", "Shadow"]
    },
    {
      "label": I18n.tr("Behaviour"),
      "fields": ["Behaviour"],
      "styles": []
    }
  ]

  // The editor tab holding a Bar field (a Bar definition key)
  function editorTabOf(key) {
    const title = BarsConfig.fieldGroups.find(group => group.keys.includes(key))?.title ?? "";
    return Math.max(0, BarsConfig.editorTabs.findIndex(tab => tab.fields.includes(title)));
  }

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
        // Its items, which Boxes: One per item draws each in a box
        // (`x-boxItems` on its `boxes` setting), null for none
        "boxItems": def.properties?.properties?.properties?.boxes?.["x-boxItems"] ?? null,
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
  // Whether a widget type shrinks when its bar is crowded (`x-elastic`):
  // its host sizes it elastic, and the editor offers its minSize and maxSize
  function isElastic(type) {
    return BarsConfig.availableWidgetTypes.find(t => t.type === type)?.elastic ?? false;
  }
  // The items a widget `entry` ({ type, properties }) draws one box each
  // (BarBoxes.expand), from config only: with Boxes: One per item, its
  // options that are on, or the list its `source` names (Markets' symbols,
  // its portfolio first; ClaudeUsage's accounts); [] for one box
  function boxItems(entry) {
    const spec = BarsConfig.availableWidgetTypes.find(t => t.type === entry.type)?.boxItems ?? null;
    const p = entry.properties ?? {};
    if (!spec || p.boxes !== "each")
      return [];
    if (spec.options)
      return BarBoxes.fromOptions(spec.options, p);
    switch (spec.source) {
    case "marketSymbols":
      return MarketMath.entries(MarketsConfig.symbols, p.symbols, p.showPortfolio).map(e => e.portfolio ? "portfolio" : e.item.id);
    case "claudeAccounts":
      return ClaudeUsageConfig.accounts.map(account => account.id);
    default:
      console.warn(`BarsConfig: ${entry.type}'s x-boxItems names no source "${spec.source}"`);
      return [];
    }
  }
  // What the bar editor's library offers: the widget types, the custom
  // widgets one by one (keyed "CustomWidget:<id>",
  // CustomWidgetsConfig.splitKey) rather than the CustomWidget type
  readonly property var libraryWidgetTypes: availableWidgetTypes.filter(t => t.type !== "CustomWidget").concat(CustomWidgetsConfig.libraryEntries(availableWidgetTypes.find(t => t.type === "CustomWidget") ?? null))
}
