pragma Singleton
import QtQuick

// Where a bar section's widget backgrounds, run backgrounds and separator
// marks go, and the room each widget keeps, from its runs (BarLayout.runs,
// runPlaces) and the bar's look: what WidgetGroup and WidgetDecorations
// place. A section's `ctx` (context) is what of the bar they read. No file
// access, processes or services.
QtObject {
  id: root

  // What of an enriched barConfig `bar` a section's runs read: its look's
  // shape and grouping, its `opaque` trait (a powerline segment may start
  // square beneath the one before), its thickness, its content's height
  // across (an icon or a label at its font size) and the loose gap (a
  // widget with no background keeps it from its neighbours in a powerline:
  // the bar's widget gap, else none)
  function context(bar) {
    const look = bar.look;
    return {
      "shape": look.shape,
      "grouping": look.grouping,
      "opaque": look.traits.opaque,
      "across": bar.thickness,
      "content": bar.fontSize,
      "looseGap": look.grouping === "powerline" ? bar.widgetGap : 0
    };
  }

  // The caps and room at `place` in a run (BarLayout.runPlaces' { index,
  // count }, null alone): BarShapes.segment's
  function segmentAt(ctx, place) {
    return BarShapes.segment(ctx.shape, ctx.grouping, ctx.opaque, place?.index ?? 0, place?.count ?? 1, ctx.across, ctx.content);
  }

  // Run flags (true: a background; false: shown without one; null: showing
  // nothing) as a string and back: a key that changes only when a flag
  // does, so what's built from the places isn't rebuilt on every new size
  function flagsKey(flags) {
    return flags.map(f => f === null ? "-" : f ? "1" : "0").join("");
  }
  function flagsOf(key) {
    return key.split("").map(c => c === "-" ? null : c === "1");
  }

  // How far a run's last widget at `place` carries on past it into the
  // next section's run, which it joins (`chainEnd`) `joinEndReach` on, else 0
  function reachOn(place, chainEnd, joinEndReach) {
    return place !== null && place.index < place.count - 1 && chainEnd ? joinEndReach : 0;
  }

  // A merged run's background, `run` (BarLayout.runs') at `places` (the
  // section's runPlaces as drawn), its widgets at `offsets` and `sizes`
  // along the section (as laid out): { first, last (its first and last
  // members), startCap, endCap (its first's start cap and its last's
  // end), openStart, openEnd (carried on from the section before, and on
  // into the next: its stroke left open there, so no divider shows at the
  // join), reach (on past its end into the next section's run, reachOn),
  // from, to (along the section, for the bar's gradient: one strip of it
  // from the run's start to its end, the reach included) }
  function runBackground(ctx, run, places, offsets, sizes, chainEnd, joinEndReach) {
    const first = run.members[0], last = run.members[run.count - 1];
    const firstPlace = places[first] ?? null, lastPlace = places[last] ?? null;
    const reach = root.reachOn(lastPlace, chainEnd, joinEndReach);
    return {
      "first": first,
      "last": last,
      "startCap": root.segmentAt(ctx, firstPlace).startCap,
      "endCap": root.segmentAt(ctx, lastPlace).endCap,
      "openStart": (firstPlace?.index ?? 0) > 0,
      "openEnd": lastPlace !== null && lastPlace.index < lastPlace.count - 1,
      "reach": reach,
      "from": offsets[first] ?? 0,
      "to": (offsets[last] ?? 0) + (sizes[last] ?? 0) + reach
    };
  }

  // The separator marks of a section whose widgets are `sizes` long as
  // allocated, `divides` (a divider of their own: the Separator), `fills`
  // (spacers), its end joining the next section (`joinEnd`): one per
  // widget, { shown, next, joined }. A mark follows a shown widget, in the
  // gap to the next shown one (`next`, -1 for none) or, after the last
  // widget (not a spacer) where the section joins the next, in the gap
  // between them (`joined`); never beside a divider.
  function marks(sizes, divides, fills, joinEnd) {
    let last = -1;
    for (let i = sizes.length - 1; i >= 0; i--) {
      if (sizes[i] > 0 && !fills[i]) {
        last = i;
        break;
      }
    }
    return sizes.map((size, i) => {
      let next = -1;
      for (let k = i + 1; k < sizes.length; k++) {
        if (sizes[k] > 0) {
          next = k;
          break;
        }
      }
      const joined = next < 0 && i === last && joinEnd;
      const between = size > 0 && (next >= 0 || joined);
      return {
        "shown": between && !(divides[i] ?? false) && !(divides[next] ?? false),
        "next": next,
        "joined": joined
      };
    });
  }

  // The room widget `index` of a section keeps along the bar at its start
  // and end ({ lead, trail }), at `place` in its run (from what it shows):
  // `host` { background (it has one), segments (it lays its parts out as
  // the run's segments, which keep their own), fills (a spacer) };
  // `section` { first, last (its first and last widgets with something to
  // show), joinStart, joinEnd (its ends join the next sections) }. With a
  // background, the room its caps keep (segmentAt); without, the loose gap
  // from a neighbour (none at the section's ends, unless joined there)
  function insets(ctx, place, host, index, section) {
    if (host.segments)
      return {
        "lead": 0,
        "trail": 0
      };
    if (host.background) {
      const s = root.segmentAt(ctx, place);
      return {
        "lead": s.lead,
        "trail": s.trail
      };
    }
    return {
      "lead": (index > section.first || section.joinStart) && !host.fills ? ctx.looseGap : 0,
      "trail": (index < section.last || section.joinEnd) && !host.fills ? ctx.looseGap : 0
    };
  }
}
