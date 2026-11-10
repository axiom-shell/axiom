pragma Singleton
import QtQuick

// A widget's parts laid out as segments of the bar's run (Workspaces with
// its Background off: its workspaces, then its strip's windows): each
// cell's caps and room in the run (cellSegment, cellRoom), the gap between
// cells (cellGap), a tab cell's fillets (cellTab), what a cell draws past
// its bounds (cellShape, cellMargins, runDraws) and where it's hit
// (cellContains). From the bar's look (look.shape, look.grouping) and a
// cell's traits (boxed, opaque), never its style's name.
QtObject {
  id: root

  // The side of the bar a widget's tooltips and cell tooltips show on: the
  // inner one, away from the screen edge `barConfig` (top, bottom, left)
  // sits on, as a Qt edge (the same value as Quickshell's Edges)
  function innerEdges(barConfig) {
    return barConfig?.top ? Qt.BottomEdge : barConfig?.bottom ? Qt.TopEdge : barConfig?.left ? Qt.RightEdge : Qt.LeftEdge;
  }

  // Cell `cell` of `cells` a widget lays out as segments of the bar's run
  // itself (Workspaces with its Background off: its workspaces, then its
  // strip's windows), the widget at `place` in its run ({ index, count },
  // BarLayout.runPlaces; null alone), in a look's `shape` and `grouping`
  // (BarShapes.segment's), its content `content` high across (segment's):
  // segment's { startCap, endCap, shownStart, back, lead, trail,
  // seamStart, seamEnd }.
  //   separate   each cell alone, in the shape's own ends
  //   powerline  the cells chain on in the bar's chain: the widget's first
  //              cell takes the cap the segment before it expects, its last
  //              ends as the widget would. Drawn over the bar's backgrounds,
  //              its first cell fits against the cap before it, never
  //              starts square beneath it; a later one does where the
  //              cells' fill hides what's under it (`opaque`, drawn under
  //              the cell before).
  //   merged     the run draws the background: a cell keeps the room of the
  //              run's end where it has one; one drawing a box of its own
  //              (`boxed`: solid boxes, split's fill) takes the caps it has
  //              alone, and their room, as a merged widget's level does
  // The room at an end keeps clear of the stroke drawn there: in a merged
  // run the run's (the look's outline), else the cell's own box's
  // (cellOutline); a box of its own in a run (`boxed`) draws its stroke
  // in its fill's color, so only its caps count.
  function cellSegment(shape, grouping, boxed, place, cell, cells, across, opaque, content) {
    const own = Object.assign({}, shape, {
      "outline": boxed ? null : root.cellOutline(shape.outline ?? null)
    });
    const lone = BarShapes.segment(own, "separate", false, 0, 1, across, content);
    const pick = (s, startCap, endCap, lead, trail) => ({
          "startCap": startCap,
          "endCap": endCap,
          // Its start as it shows (segment's): a powerline cell's past the
          // cap before, however it's drawn; else its own
          "shownStart": grouping === "powerline" ? s.shownStart : startCap,
          "back": s.back,
          "lead": lead,
          "trail": trail,
          "seamStart": s.seamStart,
          "seamEnd": s.seamEnd
        });
    if (grouping !== "powerline" && grouping !== "merged")
      return pick(lone, lone.startCap, lone.endCap, lone.lead, lone.trail);
    const index = (place?.index ?? 0) + cell;
    const count = (place?.count ?? 1) + Math.max(1, cells) - 1;
    const s = BarShapes.segment(grouping === "powerline" ? own : shape, grouping, opaque === true && cell > 0, index, count, across, content);
    if (grouping === "powerline")
      return pick(s, s.startCap, s.endCap, s.lead, s.trail);
    return pick(s, s.levelStartCap, s.levelEndCap, boxed ? lone.lead : s.lead, boxed ? lone.trail : s.trail);
  }

  // The outline a cell's own box draws (`outline`: the look's { width,
  // stroke }, or null for none): a double one in half-width lines (at
  // least 1 px), so its inner line keeps clear of the label
  function cellOutline(outline) {
    if (!outline)
      return null;
    return {
      "width": outline.stroke === "double" ? Math.max(1, Math.floor(outline.width / 2)) : outline.width,
      "stroke": outline.stroke
    };
  }

  // How a Workspaces widget's cells show on a bar's `look` (null: none
  // yet, all false), every cell a filled box (`solid`: solidBoxes), drawn
  // in the widget on the bar (`onBar`, not a popout): { boxedInRun,
  // opaque (their cell traits, BarLook.cellTraits), boxes (a box of their
  // own off a run: the sliding active box's), boxed (a box of their own
  // where they are: in a merged run on the bar, which draws their box,
  // only boxedInRun's), framed (their state shows in a box or a line,
  // else in their content), slides (the active box has something to
  // slide: a box or a line), clearsActive (the active cell clears its own
  // box under the sliding one, which a tint would show through) }
  function cellLook(look, solid, onBar) {
    if (!look)
      return {
        "boxedInRun": false,
        "opaque": false,
        "boxes": false,
        "boxed": false,
        "framed": false,
        "slides": false,
        "clearsActive": false
      };
    const traits = BarLook.cellTraits(look, solid);
    const inGroup = onBar && look.grouping === "merged";
    const boxes = look.traits.boxed || solid;
    const boxed = inGroup ? traits.boxedInRun : boxes;
    const line = look.traits.line;
    return {
      "boxedInRun": traits.boxedInRun,
      "opaque": traits.cellOpaque,
      "boxes": boxes,
      "boxed": boxed,
      "framed": boxed || line,
      "slides": boxes || line,
      "clearsActive": look.traits.tints
    };
  }

  // A Workspaces cell's length along the bar at rest, `thickness` across,
  // on `look`: square where it's boxed (`solid` too), shows numbers
  // (`labels`) or app icons (`appIcons`), else narrower, for a dot or
  // nothing straight on the bar
  function cellLength(look, solid, labels, appIcons, thickness) {
    return look.traits.boxed || solid || labels === "numbers" || appIcons ? thickness : Math.round(thickness * 0.6);
  }

  // How a cell's box is drawn (LookBox) in `look` (the bar's), in its
  // `shape` as a segment of the bar's run (cellShape) or, with none, a box
  // filling it rounded by `radius`: { outline (ShapedBox's: the segment's
  // caps, seams and tab, or round caps of `radius`), reach (past it, for
  // BarShapes.boxRect: back under the cell before, out to a tab's edge, or
  // null), strokeWidth and strokeStyle (its own box's outline: cellOutline,
  // 0 and solid for none) }
  function cellBox(look, shape, radius) {
    const s = shape?.segment ?? null;
    const outline = root.cellOutline(look.outline);
    return {
      "outline": s ? {
        "startCap": s.startCap,
        "endCap": s.endCap,
        "seamStart": s.seamStart,
        "seamEnd": s.seamEnd,
        "tab": shape.tab
      } : {
        "startCap": "round",
        "endCap": "round",
        "radius": radius
      },
      "reach": s ? {
        "back": s.back,
        "near": shape.reachStart,
        "far": shape.reachEnd
      } : null,
      "strokeWidth": outline?.width ?? 0,
      "strokeStyle": outline?.stroke ?? "solid"
    };
  }

  // The gap between a widget's cells laid out as segments (cellSegment)
  // for their own `spacing`: none in a powerline, where they chain
  function cellGap(grouping, spacing) {
    return grouping === "powerline" ? 0 : spacing;
  }

  // A tab cell's shape (BarTabs.tab), cell `cell` of `cells` (cellSegment): the
  // bar's one fillet at the widget's two ends, where `limits` (tabLimits,
  // the widget's) bound them, and between cells no more than half the
  // `gap` between them, so neighbours' fillets never cross
  function cellTab(radius, thickness, fillet, gap, outerStart, limits, cell, cells) {
    const first = cell === 0, last = cell === cells - 1;
    const t = BarTabs.tab(radius, thickness, fillet, outerStart, [first ? limits?.[0] ?? null : null, last ? limits?.[1] ?? null : null]);
    const inner = Math.max(0, Math.min(fillet, gap / 2));
    if (!first && !t.start.corner)
      t.start.flare = inner;
    if (!last && !t.end.corner)
      t.end.flare = inner;
    return t;
  }

  // Cell `cell` of `cells` on a bar `bar` (an enriched barConfig: its
  // look's shape and grouping, its thickness and radius) as a
  // segment of its widget's `run` (BarWidget.runPlace), from where the
  // widget is drawn (`run.drawn`): { segment (cellSegment), tab (cellTab,
  // on a tab bar, else null), reachStart, reachEnd (how far its box
  // reaches past it across, a tab's out to its edge), drawStart, drawEnd
  // (how far it draws past it along the bar: back under the cell before,
  // and a flared tab's fillets out past its sides) }. `boxed`, `opaque`
  // and `gap`: cellSegment's and cellTab's, and `content` the cell's
  // content's height across (WorkspaceCells.contentSize). What it draws
  // past its bounds is what every clip holding it keeps (cellMargins)
  // and, but for the fillets, where it's hovered and clicked
  // (cellContains).
  function cellShape(bar, run, boxed, opaque, gap, cell, cells, content) {
    const shape = bar.look.shape;
    const segment = root.cellSegment(shape, bar.look.grouping, boxed, run?.drawn ?? null, cell, cells, bar.thickness, opaque, content);
    const tab = shape.name === "tab" ? root.cellTab(bar.radius, bar.thickness, shape.tabFillet, gap, !(bar.right || bar.bottom), run?.tabLimits ?? null, cell, cells) : null;
    return {
      "segment": segment,
      "tab": tab,
      "reachStart": run?.reachStart ?? 0,
      "reachEnd": run?.reachEnd ?? 0,
      "drawStart": segment.back + (tab?.start.flare ?? 0),
      "drawEnd": tab?.end.flare ?? 0
    };
  }

  // What cells from `first` to `last` (cellShape's; null for none) draw
  // past the item holding them, as its margins in item coordinates:
  // { left, top, right, bottom }, the first's reach at its start, the
  // last's at its end and across out to a tab's edge. A clip holding
  // cells grows by these; a cell's hit area by its own (`first` and
  // `last` both it).
  function cellMargins(first, last, vertical) {
    const start = first?.drawStart ?? 0, end = last?.drawEnd ?? 0;
    const near = first?.reachStart ?? last?.reachStart ?? 0, far = first?.reachEnd ?? last?.reachEnd ?? 0;
    return {
      "left": vertical ? near : start,
      "top": vertical ? start : near,
      "right": vertical ? far : end,
      "bottom": vertical ? end : far
    };
  }

  // How far a widget laying its parts out as cells draws past its own ends
  // along the bar, at its place `run` (BarWidget.runPlace): its first
  // cell's reach back and its last's on, as one cell alone there would
  // draw them (cellShape's drawStart, drawEnd): { start, end }
  function runDraws(bar, run) {
    const s = root.cellShape(bar, run, false, false, 0, 0, 1);
    return {
      "start": s.drawStart,
      "end": s.drawEnd
    };
  }

  // Whether a point `x`, `y` in a cell's own coordinates (`width` by
  // `height`) lies in its `shape` (cellShape) as drawn: back under the
  // cell before from where it shows past that one's cap (its shownStart),
  // out to a tab's edge across, and short of its own end cap's cut-off
  // corners, so neighbours never answer for each other (a flared tab's
  // fillets don't count: BarShapes.contains); with no shape, its own
  // bounds
  function cellContains(shape, x, y, width, height, vertical) {
    if (!shape)
      return x >= 0 && y >= 0 && x < width && y < height;
    const s = shape.segment;
    const near = shape.reachStart, far = shape.reachEnd;
    const u = (vertical ? y : x) + s.back, v = (vertical ? x : y) + near;
    return BarShapes.contains(u, v, (vertical ? height : width) + s.back, (vertical ? width : height) + near + far, s.shownStart, s.endCap);
  }

  // The room cell `cell` of `cells` keeps clear of its caps along the bar
  // (cellSegment's lead and trail), from what its widget shows (`run.sized`,
  // never the room it's given, which this helps decide), its content
  // `content` high across (WorkspaceCells.contentSize): { lead, trail }
  function cellRoom(bar, run, boxed, cell, cells, content) {
    const s = root.cellSegment(bar.look.shape, bar.look.grouping, boxed, run?.sized ?? null, cell, cells, bar.thickness, false, content);
    return {
      "lead": s.lead,
      "trail": s.trail
    };
  }
}
