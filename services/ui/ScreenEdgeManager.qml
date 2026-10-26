pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/* What's on each screen edge: the running bars (`bars`, while the bar
 * editor has unsaved edits, those), laid out with the compositor's gaps
 * (Bar.enrichBarConfig), their windows (the bar panels), and the zones
 * open integrated edge menus reserve, with what they leave on each edge:
 * which bar is there, where windows start, where surfaces held off it
 * measure from. */
QtObject {
  id: root

  // The running bars (while the bar editor has unsaved edits, those),
  // each with what its ends meet among the bars on its screen (BarEnds:
  // which bar a shared corner goes to)
  readonly property var bars: BarEnds.withEnds(Bar.expandBars((ConfigManager.previews.Bars ?? ConfigManager.config.Bars).items).map(bar => Bar.enrichBarConfig(bar, CompositorManager.gapsOut)), Bar.endsOptions(CompositorManager.gapsOut))

  // The enabled bars on a screen by edge ({ top, bottom, left, right },
  // null where there is none)
  function edgesFor(screen) {
    return BarEnds.edgesOn(root.bars, screen?.name);
  }

  // Where the window of the bar on a screen edge (a Bar.Location) starts
  // along it at its start or end (`atStart`), in px from that end's
  // screen edge, as Hyprland arranges it (BarEnds): past the bar there it
  // makes way for, else from the frame's outer side (the screen edge for a
  // solid bar, arranged before the border), each less the bar's reach onto
  // the stroke there. Integrated menus on that edge, arranged before
  // everything, included.
  function barStartOn(screen, location, atStart) {
    const edges = root.edgesFor(screen);
    const bar = edges[Bar.edgeName(location)];
    if (!bar)
      return 0;
    const side = BarEnds.endEdges(bar)[atStart ? 0 : 1];
    const end = atStart ? bar.ends.start : bar.ends.end;
    const menus = root.zoneOn(screen?.name ?? "", side);
    const reserved = root.barReservedOn(screen, Bar.locationOf(side));
    // A solid bar is arranged before the border, which then reserves its
    // margin inside both: past the other solid bar alone
    if (BarEnds.yieldsTo(bar, edges[side]))
      return menus + reserved - (bar.solid && Appearance.screenBorder ? Appearance.screenMargin : 0) - end.reach;
    return menus + (bar.solid || !Appearance.screenBorder ? 0 : Appearance.screenMargin) - end.reach;
  }

  // What a surface's end reaching a screen edge (a Bar.Location) along a
  // perpendicular one meets there (SurfaceContext.endKind): the one answer
  // every popout, dock and pill takes its joins, walls and openings from
  function surfaceEnd(screen, location) {
    const name = Bar.edgeName(location);
    const bar = root.edgesFor(screen)[name];
    return SurfaceContext.endKind({
      "border": Appearance.screenBorder,
      "bar": bar,
      "barShowing": !bar || (root.barOn(screen?.name ?? "", location)?.visible ?? false),
      "menuZone": root.zoneOn(screen?.name ?? "", name)
    });
  }

  // Whether a screen edge (a Bar.Location) is bare: no screen border and no
  // bar on it, so surfaces there run straight off the screen
  function screenEdgeOpen(screen, location) {
    if (Appearance.screenBorder)
      return false;
    return !root.edgesFor(screen)[Bar.edgeName(location)];
  }

  // Where windows start on a screen edge (a Bar.Location), in px from it:
  // the border's and bar's reserved space, Hyprland's gaps_out not
  // included, nor integrated edge menus' zones (reservedWithMenusOn
  // adds those)
  function barReservedOn(screen, location) {
    const bar = root.edgesFor(screen)[Bar.edgeName(location)];
    const zone = bar ? Bar.reservedZone(bar, CompositorManager.gapsOut[Bar.edgeName(location)]) : 0;
    return (Appearance.screenBorder ? Appearance.screenMargin : 0) + zone - (zone > 0 && bar.insideBorder ? Appearance.borderWidth : 0);
  }

  // The inner side of what's on a screen edge, in px from it: the
  // border's stroke, or the bar there (a solid bar's inner stroke, a
  // floating bar's islands, a pill bar's far side, a transparent bar's
  // inner edge); 0 on a bare edge. Surfaces held off an edge measure their
  // gap from it (detachedGaps). Integrated edge menus' zones not included
  // (frameLineOn adds those).
  function frameLine(screen, location) {
    const bar = root.edgesFor(screen)[Bar.edgeName(location)];
    const margin = Appearance.screenBorder ? Appearance.screenMargin : 0;
    if (!bar)
      return margin;
    // Its outer edge on the border's stroke
    if (bar.insideBorder)
      return margin - Appearance.borderWidth + bar.extent;
    // The border's strip, laid over its inner part, draws its stroke
    if (bar.solid && Appearance.screenBorder)
      return bar.reserveSpace ? bar.extent + Appearance.borderWidth : margin;
    return bar.extent;
  }

  // Where the border frame's rounded inner corner lies from a screen edge
  // (a Bar.Location), in px: past a solid bar its strip (frameLine), else
  // the frame's own width, any other bar sitting inside it; 0 with the
  // border off. What an end with nothing to join keeps its fillet clear of
  // (SurfaceContext.wallAt).
  function cornerLine(screen, location) {
    if (!Appearance.screenBorder)
      return 0;
    const bar = root.edgesFor(screen)[Bar.edgeName(location)];
    return bar?.solid ? root.frameLine(screen, location) : Appearance.screenMargin;
  }

  // The gaps a surface held off a screen edge (a Bar.Location) keeps from
  // the frame lines (frameLine) across that edge and at its two ends (the
  // perpendicular edges at its start and end: top and bottom, or left and
  // right): `gap` on each when it's 0 or more. Automatic (-1), it lines up
  // with a floating bar on that edge, its float gap on all three, else
  // with the windows: how far past each frame line they start.
  function detachedGaps(screen, location, gap) {
    if (gap >= 0)
      return {
        "across": gap,
        "start": gap,
        "end": gap
      };
    const bar = root.edgesFor(screen)[Bar.edgeName(location)];
    const windowGap = side => bar?.island ? bar.floatGap : Math.max(0, root.barReservedOn(screen, side) + CompositorManager.gapsOut[Bar.edgeName(side)] - root.frameLine(screen, side));
    const vertical = location === Bar.Left || location === Bar.Right;
    return {
      "across": windowGap(location),
      "start": windowGap(vertical ? Bar.Top : Bar.Left),
      "end": windowGap(vertical ? Bar.Bottom : Bar.Right)
    };
  }

  // Space open integrated menus reserve, by "<screen>:<edge>" (edge
  // "top" | "bottom" | "left" | "right"), for surfaces that place
  // themselves against the perpendicular edges (BarPopouts)
  property var zones: ({})

  function setZone(screenName, edge, size) {
    const key = `${screenName}:${edge}`;
    if ((root.zones[key] ?? 0) !== size)
      root.zones = Utils.withEntry(root.zones, key, size > 0 ? size : undefined);
  }

  function zoneOn(screenName, edge) {
    return root.zones[`${screenName}:${edge}`] ?? 0;
  }

  // Where windows start on a screen edge (a Bar.Location), in px from it,
  // integrated menus included: what surfaces inside the reserved space
  // (floating menus, docks) are placed from (barReservedOn)
  function reservedWithMenusOn(screen, location) {
    return root.barReservedOn(screen, location) + root.zoneOn(screen?.name ?? "", Bar.edgeName(location));
  }

  // The inner side of what's on a screen edge, in px from it, integrated
  // menus included: what a surface held off an edge keeps its gaps from
  // (frameLine, detachedGaps)
  function frameLineOn(screen, location) {
    return root.frameLine(screen, location) + root.zoneOn(screen?.name ?? "", Bar.edgeName(location));
  }

  // Where the border frame's rounded inner corner lies from a screen edge,
  // integrated menus included (cornerLine)
  function cornerLineOn(screen, location) {
    return root.cornerLine(screen, location) + root.zoneOn(screen?.name ?? "", Bar.edgeName(location));
  }

  // How far past where windows start on a screen edge (a Bar.Location;
  // reservedWithMenusOn) a surface held `gap` off its frame line (frameLineOn) is:
  // where a held box goes, in from its window's edge there
  function heldInset(screen, location, gap) {
    return Math.max(0, root.frameLineOn(screen, location) + gap - root.reservedWithMenusOn(screen, location));
  }

  // The bar windows (BarPanel), for surfaces that attach to a bar without
  // being its popouts (floating edge menus)
  property var barPanels: []

  function registerBar(panel) {
    barPanels = barPanels.filter(p => p !== panel).concat([panel]);
  }

  function unregisterBar(panel) {
    barPanels = barPanels.filter(p => p !== panel);
  }

  // The enabled bar on a screen edge (a Bar.Location), or null
  function barOn(screenName, location) {
    return barPanels.find(p => p.barConfig.enabled && p.barConfig.location === location && p.screen?.name === screenName) ?? null;
  }
}
