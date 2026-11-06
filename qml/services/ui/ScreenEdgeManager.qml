pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

/* What's on each screen edge: the running bars (`bars`, while the bar
 * editor has unsaved edits, those), laid out with the compositor's gaps
 * (BarsConfig.enrichBarConfig) and stacked on their edges (BarEnds: bars
 * on one edge lie one inside the other), their windows (the bar panels),
 * and the zones open integrated edge menus reserve, with what they leave
 * on each edge: which bar is innermost there, where windows start, where
 * surfaces held off it measure from. */
QtObject {
  id: root

  // The running bars (while the bar editor has unsaved edits, those),
  // each placed in its edge's stack and with what its ends meet among the
  // bars on its screen (BarEnds.withEnds: where it lies, what it
  // reserves, which bar a shared corner goes to). An auto-hiding bar
  // pinned shown (BarRevealManager.pinned, which changes only on a pin,
  // never on hover) reserves its space.
  readonly property var bars: BarEnds.withEnds(BarsConfig.expandBars(ConfigManager.live.Bars.items).map(bar => {
    const enriched = BarsConfig.enrichBarConfig(bar, CompositorManager.gapsOut, root.floatGaps);
    enriched.pinned = enriched.autoHiding && BarRevealManager.pinned[enriched.id] === true;
    return enriched;
  }), root.endsOptions)
  readonly property var endsOptions: BarsConfig.endsOptions(CompositorManager.gapsOut, root.floatGaps)

  // The gaps a floating bar's Automatic float gap keeps (per edge name):
  // the compositor's outer gaps, or with no backend to ask, the screen
  // margin, so it isn't flush on the border (gapsOut stays 0: unknown
  // gaps aren't the margin)
  readonly property var floatGaps: CompositorManager.backend ? CompositorManager.gapsOut : ({
      "top": Appearance.screenMargin,
      "right": Appearance.screenMargin,
      "bottom": Appearance.screenMargin,
      "left": Appearance.screenMargin
    })

  // The innermost enabled bar on each edge of a screen ({ top, bottom,
  // left, right }, null where there is none): what surfaces arranged after
  // every bar meet
  function edgesFor(screen) {
    return BarEnds.edgesOn(root.bars, screen?.name);
  }

  // The enabled bars on a screen edge (a ScreenEdge), outer first
  function stackOn(screen, location) {
    return BarEnds.stacksOn(root.bars, screen?.name)[ScreenEdge.name(location)];
  }

  // What a screen edge's bars and the border leave on it (BarEnds.edgeOf:
  // reserved, frame, corner, solidZone, insideTaken, inner, facing), integrated
  // menus not counted
  function edgeOn(screen, location) {
    return BarEnds.edgeOf(root.stackOn(screen, location), root.endsOptions);
  }

  // Where the open popouts of the bars outside a bar (a `bars` entry)
  // lie over it, as spans along its edge in screen px: what gives way on
  // it while they're open (BarEnds.coveredSpans)
  function coveredOn(screen, bar) {
    if (!screen)
      return [];
    return BarEnds.coveredSpans(bar, root.stackOn(screen, bar.location), PopoutManager.entries, screen.name, root.zoneOn(screen.name, ScreenEdge.name(bar.location)), {
      "width": screen.width,
      "height": screen.height
    });
  }

  // Where a bar's window (a `bars` entry) starts along its edge at its
  // start or end (`atStart`), in px from that end's screen edge, as
  // Hyprland arranges it (BarEnds.endsOf): past the bars there it makes way
  // for, and the border for a bar inside it, less its reach onto the
  // stroke there. Integrated menus on that edge, arranged before
  // everything, included.
  function barStartOn(screen, bar, atStart) {
    const end = atStart ? bar.ends.start : bar.ends.end;
    const side = BarEnds.endEdges(bar)[atStart ? 0 : 1];
    return root.zoneOn(screen?.name ?? "", side) + end.from - end.reach;
  }

  // What a surface's end reaching a screen edge (a ScreenEdge) along a
  // perpendicular one meets there (SurfaceContext.endKind): the one answer
  // every popout, dock and pill takes its joins, walls and openings from
  function surfaceEnd(screen, location) {
    const name = ScreenEdge.name(location);
    const bar = root.edgesFor(screen)[name];
    return SurfaceContext.endKind({
      "border": Appearance.screenBorder,
      "bar": bar,
      "barShowing": !bar || (root.barOn(screen?.name ?? "", location)?.present ?? false),
      "menuZone": root.zoneOn(screen?.name ?? "", name)
    });
  }

  // Whether a screen edge (a ScreenEdge) is bare: no screen border and no
  // bar on it, so surfaces there run straight off the screen
  function screenEdgeOpen(screen, location) {
    if (Appearance.screenBorder)
      return false;
    return !root.edgesFor(screen)[ScreenEdge.name(location)];
  }

  // Where windows start on a screen edge (a ScreenEdge), in px from it:
  // the border's and every bar's reserved space there, Hyprland's gaps_out
  // not included, nor integrated edge menus' zones (reservedWithMenusOn
  // adds those)
  function barReservedOn(screen, location) {
    return root.edgeOn(screen, location).reserved;
  }

  // The inner side of what's on a screen edge, in px from it: the
  // border's stroke, or the innermost bar there (a solid bar's inner
  // stroke, a floating bar's islands, a pill bar's far side, a transparent
  // bar's inner edge); 0 on a bare edge. Surfaces held off an edge measure
  // their gap from it (detachedGaps). Integrated edge menus' zones not
  // included (frameLineOn adds those).
  function frameLine(screen, location) {
    return root.edgeOn(screen, location).frame;
  }

  // The same for one bar (a `bars` entry), wherever it lies in its edge's
  // stack (BarEnds.placeStack's `frame`), integrated menus on its edge
  // included: what its own popouts grow out of
  function barFrameLineOn(screen, bar) {
    return bar.frame + root.zoneOn(screen?.name ?? "", ScreenEdge.name(bar.location));
  }

  // Where the border frame's rounded inner corner lies from a screen edge
  // (a ScreenEdge), in px: past the solid bars there its strip, else the
  // frame's own width, any other bar sitting inside it; 0 with the border
  // off. What an end with nothing to join keeps its fillet clear of
  // (SurfaceContext.wallAt).
  function cornerLine(screen, location) {
    return root.edgeOn(screen, location).corner;
  }

  // The gaps a surface held off a screen edge (a ScreenEdge) keeps from
  // the frame lines (frameLine) across that edge and at its two ends (the
  // perpendicular edges at its start and end: top and bottom, or left and
  // right): `gap` on each when it's set. Automatic (null), it lines up
  // with a floating bar on that edge (its float gap across; its islands
  // end where windows start, BarEnds.windowInset), else with the windows:
  // how far past each frame line they start. `bare` (over a fullscreen
  // window, which covers the border and the bars): the screen's edges are
  // the frame lines, and Automatic is the gap windows keep from a bare
  // edge (floatGaps).
  function detachedGaps(screen, location, gap, bare) {
    if (gap !== null)
      return {
        "across": gap,
        "start": gap,
        "end": gap
      };
    const bar = root.edgesFor(screen)[ScreenEdge.name(location)];
    const windowGap = bare ? side => root.floatGaps[ScreenEdge.name(side)] ?? 0 : side => bar?.island && side === location ? bar.floatingGap : Math.max(0, root.barReservedOn(screen, side) + (bar?.island ? root.floatGaps : CompositorManager.gapsOut)[ScreenEdge.name(side)] - root.frameLine(screen, side));
    const vertical = location === ScreenEdge.Left || location === ScreenEdge.Right;
    return {
      "across": windowGap(location),
      "start": windowGap(vertical ? ScreenEdge.Top : ScreenEdge.Left),
      "end": windowGap(vertical ? ScreenEdge.Bottom : ScreenEdge.Right)
    };
  }

  // The gaps a box `depth` px deep held off a screen edge (a ScreenEdge)
  // keeps, `distance` (0-0.5) across the free screen from it: the
  // automatic gaps (detachedGaps), the one across that edge pushed in by
  // `distance` of the room left between the automatic gaps on that edge
  // and the opposite one, so 0 is where the automatic gap holds it and 0.5
  // centres it. Every detached surface (an OSD, a dock, a floating edge
  // menu, the launcher, the window switcher) is placed by it.
  function heldGaps(screen, location, distance, depth, bare) {
    const gaps = root.detachedGaps(screen, location, null, bare);
    if (!(distance > 0))
      return gaps;
    const far = ScreenEdge.opposite(location);
    const line = side => bare ? 0 : root.frameLineOn(screen, side);
    const vertical = location === ScreenEdge.Left || location === ScreenEdge.Right;
    const span = (vertical ? screen?.width : screen?.height) ?? 0;
    const room = span - line(location) - gaps.across - line(far) - root.detachedGaps(screen, far, null, bare).across;
    return {
      "across": gaps.across + Math.min(distance, 0.5) * Math.max(0, room - depth),
      "start": gaps.start,
      "end": gaps.end
    };
  }

  // Space open integrated menus reserve, by menu id: { screen, edge
  // ("top" | "bottom" | "left" | "right"), size }, for surfaces that place
  // themselves against the perpendicular edges (BarPopouts). A menu's
  // replaces what it set before, so one that moves edge or screen leaves
  // nothing behind; 0 clears it
  property var zones: ({})

  function setZone(menuId, screenName, edge, size) {
    const old = root.zones[menuId];
    if ((old?.size ?? 0) === size && (size === 0 || (old.screen === screenName && old.edge === edge)))
      return;
    root.zones = Utils.withEntry(root.zones, menuId, size > 0 ? {
      "screen": screenName,
      "edge": edge,
      "size": size
    } : undefined);
  }

  // What the menus open on a screen edge reserve, together
  function zoneOn(screenName, edge) {
    return Object.values(root.zones).filter(zone => zone.screen === screenName && zone.edge === edge).reduce((sum, zone) => sum + zone.size, 0);
  }

  // Where windows start on a screen edge (a ScreenEdge), in px from it,
  // integrated menus included: what surfaces inside the reserved space
  // (floating menus, docks) are placed from (barReservedOn)
  function reservedWithMenusOn(screen, location) {
    return root.barReservedOn(screen, location) + root.zoneOn(screen?.name ?? "", ScreenEdge.name(location));
  }

  // The inner side of what's on a screen edge, in px from it, integrated
  // menus included: what a surface held off an edge keeps its gaps from
  // (frameLine, detachedGaps)
  function frameLineOn(screen, location) {
    return root.frameLine(screen, location) + root.zoneOn(screen?.name ?? "", ScreenEdge.name(location));
  }

  // Where the border frame's rounded inner corner lies from a screen edge,
  // integrated menus included (cornerLine)
  function cornerLineOn(screen, location) {
    return root.cornerLine(screen, location) + root.zoneOn(screen?.name ?? "", ScreenEdge.name(location));
  }

  // How far past where windows start on a screen edge (a ScreenEdge;
  // reservedWithMenusOn) a surface held `gap` off its frame line (frameLineOn) is:
  // where a held box goes, in from its window's edge there. `bare` (over a
  // fullscreen window: its window spans the screen): `gap` from the
  // screen's edge
  function heldInset(screen, location, gap, bare) {
    if (bare)
      return Math.max(0, gap);
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

  // The window of the innermost enabled bar on a screen edge (a
  // ScreenEdge), or with `barId`, of that bar there; else null
  function barOn(screenName, location, barId) {
    const id = barId || (BarEnds.edgesOn(root.bars, screenName)[ScreenEdge.name(location)]?.id ?? "");
    if (id === "")
      return null;
    return barPanels.find(p => p.barConfig.enabled && p.barConfig.id === id && p.barConfig.location === location && p.screen?.name === screenName) ?? null;
  }
}
