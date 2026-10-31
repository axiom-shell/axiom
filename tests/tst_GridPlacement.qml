import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "GridPlacement"

  function at(x, y, w, h) {
    return {
      "type": "Test",
      "place": {
        "x": x,
        "y": y,
        "w": w,
        "h": h
      }
    };
  }

  function test_span() {
    // cardUnit 500, cardSpacing 20: a grid unit is 110
    compare(GridPlacement.unitOf(500), 110);
    compare(GridPlacement.span(1, 500), 110);
    compare(GridPlacement.span(2, 500), 240, "two units are half a card");
    compare(GridPlacement.span(4, 500), 500, "four units are one card");
    compare(GridPlacement.span(8, 500), 1020, "two cards and the gap between");
    compare(GridPlacement.span(4, 300), 300, "at another card size");
  }

  function test_cards() {
    compare(GridPlacement.cards(4), "1");
    compare(GridPlacement.cards(2), "½");
    compare(GridPlacement.cards(5), "1¼");
    compare(GridPlacement.cards(11), "2¾");
  }

  function test_shapes() {
    compare(GridPlacement.slotShape([0, 0, 2, 2]), "square");
    compare(GridPlacement.slotShape([0, 0, 2, 1]), "horizontal");
    compare(GridPlacement.slotShape([0, 0, 1, 2]), "vertical");
    compare(GridPlacement.slotShape([0, 0, 5, 4]), "square", "near square counts as square");
    compare(GridPlacement.slotShape([0, 0, 4, 3]), "square");
    compare(GridPlacement.slotShape([0, 0, 3, 2]), "horizontal", "from 1.5 times as wide");
    compare(GridPlacement.slotShape([0, 0, 4, 6]), "vertical");
    compare(GridPlacement.slotShape([0, 0, 8, 1]), "horizontal");
    compare(GridPlacement.rectOf({
      "x": 3,
      "y": 1,
      "w": 2,
      "h": 4
    }), [3, 1, 2, 4]);
  }

  function test_bounds() {
    compare(GridPlacement.bounds([]), {
      "cols": 0,
      "rows": 0
    });
    compare(GridPlacement.bounds([at(0, 0, 2, 4), at(2, 1, 4, 2)]), {
      "cols": 6,
      "rows": 4
    });
  }

  function test_revealOrder() {
    compare(GridPlacement.revealOrder([]), []);
    // Diagonals first (x + y), the higher of a diagonal first, then config order
    compare(GridPlacement.revealOrder([at(4, 0, 4, 4), at(0, 0, 4, 4), at(0, 4, 4, 4), at(4, 4, 4, 4), at(2, 2, 2, 2)]), [1, 0, 3, 4, 2]);
    // Infinity - Infinity is NaN: placeless modules keep config order, last
    compare(GridPlacement.revealOrder([
      {},
      at(0, 0, 2, 2),
      {}
    ]), [1, 0, 2]);
  }

  function test_canPlace() {
    const modules = [at(0, 0, 2, 2), at(2, 0, 2, 1)];
    verify(GridPlacement.canPlace(modules, {
      "x": 2,
      "y": 1,
      "w": 2,
      "h": 1
    }, -1), "the hole beside");
    verify(!GridPlacement.canPlace(modules, {
      "x": 1,
      "y": 1,
      "w": 2,
      "h": 1
    }, -1), "overlaps the first");
    verify(GridPlacement.canPlace(modules, {
      "x": 1,
      "y": 0,
      "w": 2,
      "h": 2
    }, 0) === false, "still overlaps the second");
    verify(GridPlacement.canPlace(modules, {
      "x": 0,
      "y": 1,
      "w": 2,
      "h": 2
    }, 0), "a module may overlap where it was");
    verify(!GridPlacement.canPlace(modules, {
      "x": -1,
      "y": 0,
      "w": 1,
      "h": 1
    }, -1), "off the grid");
    verify(!GridPlacement.canPlace(modules, {
      "x": 5,
      "y": 0,
      "w": 0,
      "h": 1
    }, -1), "no size");
  }

  function test_firstFree() {
    compare(GridPlacement.firstFree([], 2, 2), {
      "x": 0,
      "y": 0,
      "w": 2,
      "h": 2
    });
    // A hole at (2, 1) in a 4 × 2 grid
    const modules = [at(0, 0, 2, 2), at(2, 0, 2, 1), at(3, 1, 1, 1)];
    compare(GridPlacement.firstFree(modules, 1, 1), {
      "x": 2,
      "y": 1,
      "w": 1,
      "h": 1
    });
    compare(GridPlacement.firstFree(modules, 2, 2), {
      "x": 4,
      "y": 0,
      "w": 2,
      "h": 2
    }, "no room inside: to the right");
    compare(GridPlacement.firstFree([at(0, 0, 8, 2)], 2, 2), {
      "x": 0,
      "y": 2,
      "w": 2,
      "h": 2
    }, "a wide grid grows down");
  }

  function p(x, y, w, h) {
    return at(x, y, w, h).place;
  }

  function test_normalize_hold() {
    const modules = [at(2, 3, 1, 1), at(4, 5, 1, 1)];
    compare(GridPlacement.normalize(modules, {
      "y": true
    }), {
      "x": 2,
      "y": 0
    }, "a gap before them stays on a held axis");
    compare(modules[0].place, p(0, 3, 1, 1));
    const negative = [at(0, -2, 1, 1)];
    compare(GridPlacement.normalize(negative, {
      "y": true
    }), {
      "x": 0,
      "y": -2
    }, "but nothing stays negative");
  }

  function test_clearOf() {
    verify(GridPlacement.clearOf([p(0, 0, 2, 2)], p(2, 0, 1, 1), -1, null));
    verify(!GridPlacement.clearOf([p(0, 0, 2, 2)], p(1, 1, 1, 1), -1, null));
    verify(GridPlacement.clearOf([p(0, 0, 2, 2)], p(1, 1, 1, 1), 0, null), "its own place ignored");
    verify(GridPlacement.clearOf([null], p(-2, -1, 1, 1), -1, null), "negative without an area");
    verify(!GridPlacement.clearOf([], p(-1, 0, 1, 1), -1, {
      "cols": 4,
      "rows": 4
    }), "outside the area");
  }

  function test_push() {
    const down = {
      "x": 0,
      "y": 1
    };
    // A column of three: a new module on top pushes all of them down
    const column = [p(0, 0, 2, 2), p(0, 2, 2, 2), p(0, 4, 2, 2)];
    compare(GridPlacement.push(column, -1, p(0, 0, 2, 1), down, null), [p(0, 1, 2, 2), p(0, 3, 2, 2), p(0, 5, 2, 2), p(0, 0, 2, 1)]);
    compare(column[0], p(0, 0, 2, 2), "the input isn't changed");
    // Only what's hit moves
    compare(GridPlacement.push([p(0, 0, 2, 2), p(4, 0, 2, 2)], -1, p(0, 1, 1, 1), down, null), [p(0, 2, 2, 2), p(4, 0, 2, 2), p(0, 1, 1, 1)]);
    // A move: its old place is free
    compare(GridPlacement.push([p(0, 0, 2, 2), p(0, 2, 2, 2)], 1, p(0, 0, 2, 2), down, null), [p(0, 2, 2, 2), p(0, 0, 2, 2)]);
    // The other directions
    compare(GridPlacement.push([p(0, 0, 2, 2)], -1, p(0, 1, 2, 2), {
      "x": 0,
      "y": -1
    }, null), [p(0, -1, 2, 2), p(0, 1, 2, 2)]);
    compare(GridPlacement.push([p(0, 0, 2, 2)], -1, p(1, 0, 1, 1), {
      "x": 1,
      "y": 0
    }, null), [p(2, 0, 2, 2), p(1, 0, 1, 1)]);
    compare(GridPlacement.push([p(0, 0, 2, 2)], -1, p(1, 0, 1, 1), {
      "x": -1,
      "y": 0
    }, null), [p(-1, 0, 2, 2), p(1, 0, 1, 1)]);
    // Pushed into the module put (wider than what hit it): past it too
    compare(GridPlacement.push([p(0, 0, 1, 1), p(0, 1, 1, 1)], 0, p(0, 1, 1, 3), down, null), [p(0, 1, 1, 3), p(0, 4, 1, 1)]);
    // Out of a bounded area: refused
    compare(GridPlacement.push([p(0, 0, 4, 2), p(0, 2, 4, 2)], -1, p(0, 0, 4, 1), down, {
      "cols": 4,
      "rows": 4
    }), null);
    verify(GridPlacement.push([p(0, 0, 4, 2)], -1, p(0, 0, 4, 1), down, {
      "cols": 4,
      "rows": 4
    }) !== null);
  }

  function test_grown() {
    // A notifications column over two cards, beside a third that stays
    const places = [p(0, 0, 4, 2), p(0, 2, 4, 2), p(0, 4, 4, 2), p(4, 0, 4, 2)];
    compare(GridPlacement.grown(places, [2, 0, 0, 0]), [p(0, 0, 4, 4), p(0, 4, 4, 2), p(0, 6, 4, 2), p(4, 0, 4, 2)], "pushes its column down, not the one beside it");
    compare(places[0], p(0, 0, 4, 2), "the input isn't changed");
    compare(GridPlacement.grown(places, []), places, "no growth: as placed");
    // A gap under it is taken first
    compare(GridPlacement.grown([p(0, 0, 4, 2), p(0, 4, 4, 2)], [3]), [p(0, 0, 4, 5), p(0, 5, 4, 2)]);
    // Only what it reaches: a module half under it moves, one past its
    // columns doesn't
    compare(GridPlacement.grown([p(0, 0, 2, 2), p(1, 2, 2, 2), p(2, 0, 2, 2)], [1]), [p(0, 0, 2, 3), p(1, 3, 2, 2), p(2, 0, 2, 2)]);
    // Two growing: the lower grows from where it's pushed to
    compare(GridPlacement.grown([p(0, 0, 2, 2), p(0, 2, 2, 2), p(0, 4, 2, 2)], [1, 1, 0]), [p(0, 0, 2, 3), p(0, 3, 2, 3), p(0, 6, 2, 2)]);
    // Nulls are skipped
    compare(GridPlacement.grown([null, p(0, 0, 2, 2)], [5, 1]), [null, p(0, 0, 2, 3)]);
    // Free rows towards the edge (above) go first, then it grows away
    compare(GridPlacement.grown([p(0, 2, 2, 2), p(0, 4, 2, 2)], [1]), [p(0, 1, 2, 3), p(0, 4, 2, 2)], "up into the gap");
    compare(GridPlacement.grown([p(0, 2, 2, 2), p(0, 4, 2, 2)], [3]), [p(0, 0, 2, 5), p(0, 5, 2, 2)], "the gap, then down");
    // Only up to a module above it in its columns
    compare(GridPlacement.grown([p(0, 0, 2, 1), p(0, 2, 2, 2), p(4, 0, 2, 4)], [0, 2]), [p(0, 0, 2, 1), p(0, 1, 2, 4), p(4, 0, 2, 4)]);
    // Towards a bottom edge: down into the free rows (not past the grid's
    // last), then up, pushing what's above it up; shifted back to row 0
    compare(GridPlacement.grown([p(0, 0, 2, 2), p(0, 3, 2, 1)], [1], 1), [p(0, 0, 2, 3), p(0, 3, 2, 1)], "down into the gap");
    compare(GridPlacement.grown([p(0, 0, 2, 2), p(0, 2, 2, 1), p(2, 0, 2, 4)], [2], 1), [p(0, 0, 2, 4), p(0, 4, 2, 1), p(2, 2, 2, 4)], "no gap: up, the grid growing at the top");
    compare(GridPlacement.grown([p(0, 0, 2, 2), p(0, 2, 2, 2)], [0, 2], 1), [p(0, 0, 2, 2), p(0, 2, 2, 4)], "pushes what's above it up");
    // Alone, which way it goes
    compare(GridPlacement.growthAround([p(0, 2, 2, 2), p(0, 4, 2, 2)], 0, 3), {
      "up": 2,
      "down": 1
    });
    compare(GridPlacement.growthAround([p(0, 0, 2, 2), p(0, 3, 2, 1)], 0, 2, 1), {
      "up": 1,
      "down": 1
    });
    compare(GridPlacement.growthAround([p(0, 0, 2, 2)], 0, 0), {
      "up": 0,
      "down": 0
    });
  }

  function test_pushGroup() {
    const down = {
      "x": 0,
      "y": 1
    };
    // Two side by side moved onto a wide one: it goes under both
    compare(GridPlacement.pushGroup([p(0, 0, 4, 1), p(0, 2, 2, 1), p(2, 2, 2, 1)], [[1, p(0, 0, 2, 1)], [2, p(2, 0, 2, 1)]], down, null), [p(0, 1, 4, 1), p(0, 0, 2, 1), p(2, 0, 2, 1)]);
    // Pushed into the lower of a group: past it too
    compare(GridPlacement.pushGroup([p(0, 0, 1, 1), p(5, 5, 1, 1), p(5, 6, 1, 1)], [[1, p(0, 0, 1, 1)], [2, p(0, 1, 1, 1)]], down, null), [p(0, 2, 1, 1), p(0, 0, 1, 1), p(0, 1, 1, 1)]);
  }

  function test_cover() {
    compare(GridPlacement.cover([p(1, 1, 1, 1), null, p(3, 0, 2, 4)]), p(1, 0, 4, 4));
    compare(GridPlacement.cover([]), null);
  }

  function test_fitPlace() {
    // A 2 × 2 hole at (2, 0) between two columns
    const places = [p(0, 0, 2, 4), p(4, 0, 2, 4)];
    const area = {
      "cols": 6,
      "rows": 2
    };
    compare(GridPlacement.fitPlace(places, {
      "x": 3,
      "y": 1
    }, [4, 4], [1, 1], area), p(2, 0, 2, 2), "shrinks into the hole");
    compare(GridPlacement.fitPlace(places, {
      "x": 0,
      "y": 0
    }, [4, 4], [1, 1], area), null, "the cell is taken");
    compare(GridPlacement.fitPlace(places, {
      "x": 3,
      "y": 1
    }, [4, 4], [3, 3], area), null, "smaller than the least size");
    // Room enough: its full size, centred on the cell
    compare(GridPlacement.fitPlace([], {
      "x": 5,
      "y": 5
    }, [4, 2], [1, 1], null), p(4, 5, 4, 2));
    // Of equal areas, the one shaped like what's wanted: a 4 × 1 strip
    // row free above a module 2 wide, wanting 4 × 2
    compare(GridPlacement.fitPlace([p(0, 1, 2, 1), p(2, 1, 2, 1)], {
      "x": 1,
      "y": 0
    }, [4, 2], [1, 1], {
      "cols": 4,
      "rows": 2
    }), p(0, 0, 4, 1));
  }

  function test_resizeFrom() {
    const place = p(2, 2, 2, 2);
    compare(GridPlacement.resizeFrom(place, "se", 1, 2), p(2, 2, 3, 4));
    compare(GridPlacement.resizeFrom(place, "e", 1, 5), p(2, 2, 3, 2), "an edge moves one side");
    compare(GridPlacement.resizeFrom(place, "s", 5, 1), p(2, 2, 2, 3));
    compare(GridPlacement.resizeFrom(place, "nw", -1, -2), p(1, 0, 3, 4), "the bottom right stays");
    compare(GridPlacement.resizeFrom(place, "n", 0, 1), p(2, 3, 2, 1));
    compare(GridPlacement.resizeFrom(place, "w", -2, 0), p(0, 2, 4, 2));
    compare(GridPlacement.resizeFrom(place, "ne", 1, -1), p(2, 1, 3, 3));
    compare(GridPlacement.resizeFrom(place, "sw", 1, 1), p(3, 2, 1, 3));
    compare(GridPlacement.resizeFrom(place, "nw", 5, 5), p(3, 3, 1, 1), "never below one unit, never flipped");
    compare(GridPlacement.resizeFrom(place, "se", 50, 0), p(2, 2, 32, 2), "at most maxSpan");
  }

  function test_firstFreeIn() {
    compare(GridPlacement.firstFreeIn([], 2, 2, 4, 4), at(0, 0, 2, 2).place);
    compare(GridPlacement.firstFreeIn([at(0, 0, 2, 2)], 2, 2, 4, 4), at(2, 0, 2, 2).place);
    compare(GridPlacement.firstFreeIn([at(0, 0, 4, 2)], 2, 2, 4, 4), at(0, 2, 2, 2).place);
    compare(GridPlacement.firstFreeIn([at(0, 0, 4, 4)], 1, 1, 4, 4), null);
    compare(GridPlacement.firstFreeIn([], 5, 1, 4, 4), null);
  }

  function test_scalePlace() {
    compare(GridPlacement.scalePlace(at(1, 2, 3, 4).place, true), at(2, 4, 6, 8).place);
    compare(GridPlacement.scalePlace(at(0, 0, 20, 1).place, true), at(0, 0, 32, 2).place);
    compare(GridPlacement.scalePlace(at(2, 4, 6, 8).place, false), at(1, 2, 3, 4).place);
    // Odd edges round, so neighbours still meet
    compare(GridPlacement.scalePlace(at(0, 0, 3, 1).place, false), at(0, 0, 2, 1).place);
    compare(GridPlacement.scalePlace(at(3, 0, 3, 1).place, false), at(2, 0, 1, 1).place);
    compare(GridPlacement.scalePlace(at(1, 1, 1, 1).place, false), at(1, 1, 1, 1).place);
  }

  function test_within() {
    verify(GridPlacement.within(at(0, 0, 4, 4).place, 4, 4));
    verify(GridPlacement.within(at(2, 3, 2, 1).place, 4, 4));
    verify(!GridPlacement.within(at(3, 0, 2, 1).place, 4, 4));
    verify(!GridPlacement.within(at(0, 4, 1, 1).place, 4, 4));
    verify(!GridPlacement.within(null, 4, 4));
  }

  function test_latticeUnit() {
    // 16 × 9 on 2560 × 1440 with 20 px margins: height decides, the gaps
    // `ratio` px per px of card
    const ratio = GridPlacement.cardSpacing / 500;
    const card = GridPlacement.latticeUnit(16, 9, 2560, 1440, 20, ratio);
    const gap = card * ratio;
    const sizes = GridPlacement.trackSizes({
      "cols": 16,
      "rows": 9
    }, card, null, gap);
    verify(sizes.height <= 1400 && sizes.height > 1400 - 9, "nine rows fill the height");
    verify(sizes.width < 2520, "the width has room left");
    const stretched = GridPlacement.trackSizes({
      "cols": 16,
      "rows": 9
    }, card, {
      "width": 2520,
      "height": 1400
    }, gap);
    compare(Math.round(stretched.width), 2520);
    compare(Math.round(stretched.height), 1400);
    // A portrait screen: width decides
    const portrait = GridPlacement.latticeUnit(16, 9, 1080, 1920, 20, ratio);
    const across = GridPlacement.trackSizes({
      "cols": 16,
      "rows": 9
    }, portrait, null, portrait * ratio).width;
    verify(across <= 1040 && across > 1040 - 16);
  }

  // Two units of a double grid and the gap between them are one unit, so
  // any span doubled is as long (within rounding)
  function test_fineUnit() {
    [280, 360, 431].forEach(unit => {
      const fine = GridPlacement.fineUnit(unit);
      [1, 2, 3, 4, 8, 16].forEach(n => verify(Math.abs(GridPlacement.span(n * 2, fine) - GridPlacement.span(n, unit)) <= n, `${n} units at ${unit}`));
    });
  }

  function test_screenGrid() {
    compare(GridPlacement.screenGrid({
      "columns": 16,
      "rows": 9
    }), {
      "cols": 16,
      "rows": 9
    });
    compare(GridPlacement.screenGrid({
      "columns": 16,
      "rows": 9,
      "fine": true
    }), {
      "cols": 32,
      "rows": 18
    });
    compare(GridPlacement.screenGrid(null), {
      "cols": 0,
      "rows": 0
    });
  }

  function test_normalize() {
    const modules = [at(2, 1, 2, 2), at(4, 3, 1, 1)];
    compare(GridPlacement.normalize(modules), {
      "x": 2,
      "y": 1
    });
    compare(modules[0].place.x, 0);
    compare(modules[0].place.y, 0);
    compare(modules[1].place.x, 2);
    compare(modules[1].place.y, 2);
    compare(GridPlacement.normalize(modules), {
      "x": 0,
      "y": 0
    }, "already at 0");
    compare(GridPlacement.normalize([]), {
      "x": 0,
      "y": 0
    });
  }

  // A 500 px card's unit is 110 px, a step (unit + gap) 130 px. A 1000 px
  // edge with 10 px pads holds 7 cells (890 px), centred from 55 px
  function lattice(shift) {
    return GridPlacement.menuLattice(1000, 500, 10, 10, shift);
  }

  function test_menuLattice() {
    compare(GridPlacement.stepOf(500), 130);
    const l = lattice(0);
    compare([l.origin, l.step, l.cols, l.first, l.last, l.startPad], [55, 130, 7, 0, 6, 10]);
    compare([lattice(40).origin, lattice(40).first, lattice(40).last], [95, 0, 6], "moved, every cell still inside");
    compare(lattice(70).last, 5, "moved past the end: the last cell drops out");
    compare(lattice(-50).first, 1, "and past the start");
    compare(GridPlacement.menuLattice(910, 500, 10, 10, 0).cols, 7, "a room exactly 7 cells long holds 7");
  }

  function test_alongStart() {
    const l = lattice(0);
    compare(GridPlacement.alongStart(l, 0, 2), 315, "centred: cell 2 of 7");
    compare(GridPlacement.alongStart(l, 0, 3), 315, "one longer: the same cells, not half a cell over");
    compare(GridPlacement.alongStart(l, 0, 4), 185);
    compare(GridPlacement.alongStart(l, 1, 2), 445);
    compare(GridPlacement.alongStart(l, 10, 2), 705, "kept on the lattice");
    compare(GridPlacement.alongStart(l, -10, 2), 55);
    compare(GridPlacement.alongStart(lattice(40), 0, 2), 355, "a moved lattice moves it by px, on the same cell");
    compare(GridPlacement.alongStart(lattice(70), 10, 2), 125 + 4 * 130, "kept off a cell that dropped out");
    compare(GridPlacement.menuCell(l, 0, 8), null);
    compare(GridPlacement.alongStart(l, 0, 8), 10, "longer than the lattice: from its start");
  }

  function test_offsetRange() {
    const l = lattice(0);
    function range(units) {
      const r = GridPlacement.offsetRange(l, units);
      return [r.min, r.max];
    }
    compare(range(2), [-2, 3]);
    compare(range(7), [0, 0], "filling the lattice");
    compare(range(8), [0, 0], "longer than it");
    compare(GridPlacement.offsetFor(l, 4, 2), 2);
    for (let cell = 0; cell <= 5; cell++)
      compare(GridPlacement.menuCell(l, GridPlacement.offsetFor(l, cell, 2), 2), cell, `round trip at cell ${cell}`);
  }

  function test_screenBox() {
    // As [x, y, w, h] in px (a step is 130 px), as compare() doesn't
    // compare objects by value
    function box(edge, along, across) {
      const b = GridPlacement.screenBox(1020, 500, 500, {
        "cols": 2,
        "rows": 2
      }, edge, along, across);
      return [b.x, b.y, b.w, b.h].map(v => Math.round(v * 130));
    }
    // Its sides lie midway in the gaps: half a gap (10 px) on
    compare(box("left", 0, 0), [10, 10, 1020, 500], "at the start, against the edge");
    compare(box("left", 130, 20), [-10, -120, 1020, 500], "a step along, 20 px in");
    // The grid is 240 px across: the screen's right side is 20 px past it
    compare(box("right", 0, 20), [-750, 10, 1020, 500], "against a right edge");
    compare(box("top", 260, 0), [-250, 10, 1020, 500], "along a top edge");
    compare(box("bottom", 0, 0).slice(1, 2), [-250], "against a bottom edge");
  }

  // A rect as [x, y, width, height], as compare() doesn't compare objects
  // by value
  function r4(r) {
    return [r.x, r.y, r.width, r.height].map(v => Math.round(v * 100) / 100);
  }

  function test_baseCard_and_zoomOf() {
    // Two cards and a gap fill the short side less 80 px each side
    compare(GridPlacement.baseCard(1920, 1080), 450, "1080p");
    compare(GridPlacement.baseCard(1080, 1920), 450, "the same monitor turned");
    compare(GridPlacement.baseCard(3440, 1440), 630, "1440p ultrawide");
    compare(GridPlacement.baseCard(100, 100), 1, "never nothing");
    compare(GridPlacement.zoomOf(0.8), 0.8, "a menu at 80 %");
    compare(GridPlacement.zoomOf(1.01), 1, "within 2 %: as laid out");
    compare(GridPlacement.gridUnitOf(472.4, false, 20), 472);
    compare(GridPlacement.gridUnitOf(590, true, 20), 285, "a double grid's units");
    compare(GridPlacement.layoutReach([null,
      {
        "x": 14,
        "y": 0,
        "w": 4,
        "h": 2
      }
    ], {
      "cols": 16,
      "rows": 9
    }), {
      "cols": 18,
      "rows": 9
    }, "as far as the modules reach past their grid");
  }

  // A grid drawn at `zoom`, its cards and gapOf's gaps, is the grid at 1
  // scaled: every place's rect
  function test_gapOf() {
    compare(GridPlacement.gapOf(1), GridPlacement.cardSpacing, "the layout's own");
    compare(GridPlacement.gapOf(0.5), GridPlacement.cardSpacing / 2);
    const bounds = {
      "cols": 6,
      "rows": 5
    };
    const place = at(1, 2, 3, 2).place;
    const zoom = 0.73;
    const layout = GridPlacement.trackSizes(bounds, 450, null, GridPlacement.gapOf(1));
    const drawn = GridPlacement.trackSizes(bounds, 450 * zoom, null, GridPlacement.gapOf(zoom));
    fuzzyCompare(drawn.width, layout.width * zoom, 1e-6);
    fuzzyCompare(drawn.height, layout.height * zoom, 1e-6);
    const a = GridPlacement.rectPx(place, layout);
    const b = GridPlacement.rectPx(place, drawn);
    ["x", "y", "width", "height"].forEach(key => fuzzyCompare(b[key], a[key] * zoom, 1e-6, key));
  }

  function test_overlayLayout() {
    // cardSpacing 20: two cards high is two cards and a gap
    const ultrawide = GridPlacement.overlayLayout(1199, 630, 1);
    compare([ultrawide.drawn, ultrawide.unit, ultrawide.zoom], [589, 589, 1], "1440p ultrawide with a bar: two cards fill the height, never a pixel over");
    const fhd = GridPlacement.overlayLayout(870, 450, 1);
    compare([fhd.drawn, fhd.unit, fhd.zoom], [425, 425, 1], "1080p: smaller cards, content at its own size");
    compare(GridPlacement.overlayLayout(2000, 450, 1).drawn, 450, "room to spare: the card size");
    const bigger = GridPlacement.overlayLayout(1199, 756, 1.2);
    compare([bigger.drawn, bigger.unit, bigger.zoom], [587, 489, 1.2], "a bigger Module size zooms the content, its gap too");
    // At the defaults a page two cards high, coarse or double grid, fits
    // unshrunk wherever the height limits the cards
    [[1207, 630, 1], [1191, 630, 1], [1199, 756, 1.2], [871, 450, 1]].forEach(([height, card, zoom]) => {
      const layout = GridPlacement.overlayLayout(height, card, zoom);
      compare(GridPlacement.fitScale({
        "cols": 8,
        "rows": 8
      }, 4000, height / zoom, layout.unit), 1, `${height} px, coarse`);
      compare(GridPlacement.fitScale({
        "cols": 16,
        "rows": 16
      }, 4000, height / zoom, GridPlacement.fineUnit(layout.unit)), 1, `${height} px, double grid`);
    });
    compare(GridPlacement.overlayLayout(1, 1, 1).drawn, 1, "never nothing");
  }

  function test_screenLattice() {
    // card 425: unit (425 - 60) / 4 = 91.25, step 111.25
    // 17 × 9 fit: each count rounded down to even, so the centre falls
    // between units
    compare(GridPlacement.screenLattice(425, 1920, 1080, 20), {
      "cols": 16,
      "rows": 8
    }, "1080p");
    // At each screen's own card size (baseCard: 450 px at 1080p, 630 px
    // at 1440p), where 16 × 9, 15 × 8 and 21 × 8 fit
    [[1920, 1080, 16, 8], [2560, 1440, 14, 8], [3440, 1440, 20, 8]].forEach(([width, height, cols, rows]) => {
      compare(GridPlacement.screenLattice(GridPlacement.baseCard(width, height), width, height, 20), {
        "cols": cols,
        "rows": rows
      }, `${width} × ${height}`);
    });
    compare(GridPlacement.screenLattice(425, 2560, 1080, 20).cols, 22, "21:9: more across, as many down");
    compare(GridPlacement.screenLattice(850, 1920, 1080, 20), {
      "cols": 8,
      "rows": 4
    }, "cards twice the size: half as many");
    compare(GridPlacement.screenLattice(425, 10, 10, 20), {
      "cols": 1,
      "rows": 1
    }, "never none");
  }

  function test_evenCount() {
    compare([1, 2, 3, 9, 10].map(count => GridPlacement.evenCount(count, false)), [1, 2, 2, 8, 10], "down");
    compare([1, 2, 3, 9, 10].map(count => GridPlacement.evenCount(count, true)), [1, 2, 4, 10, 10], "up");
  }

  function test_anchorPlaces() {
    const from = {
      "cols": 16,
      "rows": 9
    };
    const corner = {
      "x": 13,
      "y": 6,
      "w": 3,
      "h": 3
    };
    const topLeft = {
      "x": 0,
      "y": 0,
      "w": 4,
      "h": 2
    };
    const middle = {
      "x": 6,
      "y": 3,
      "w": 4,
      "h": 3
    };
    compare(GridPlacement.anchorPlaces([topLeft, corner, middle, null], from, from), [topLeft, corner, middle, null], "same grid: unmoved");
    const wide = GridPlacement.anchorPlaces([topLeft, corner, middle], from, {
      "cols": 22,
      "rows": 9
    });
    compare(wide[0], topLeft, "the start stays");
    compare(wide[1].x, 19, "the end keeps to the end");
    compare(wide[1].y, 6);
    compare(wide[2].x, 9, "the middle keeps centred");
    const small = GridPlacement.anchorPlaces([topLeft, corner, middle], from, {
      "cols": 13,
      "rows": 7
    });
    compare([small[1].x, small[1].y], [10, 4], "a corner on a smaller grid");
    compare([small[2].x, small[2].y], [5, 2]);
    compare(GridPlacement.anchorPlaces([topLeft,
      {
        "x": 13,
        "y": 0,
        "w": 3,
        "h": 3
      }
    ], from, {
      "cols": 6,
      "rows": 9
    }), null, "left and right meet: null");
    compare(GridPlacement.anchorPlaces([
      {
        "x": 0,
        "y": 0,
        "w": 16,
        "h": 2
      }
    ], from, {
      "cols": 12,
      "rows": 9
    }), null, "too wide for the grid: null");
  }

  function test_anchorPlaces_moves_touching_modules_as_one() {
    // A centred stack low on the screen: its parts touch, so it moves as
    // one and keeps its shape; alone, its bottom part would go to the end
    // and its top part stay centred, landing on each other
    const stack = [
      {
        "x": 6,
        "y": 4,
        "w": 4,
        "h": 2
      },
      {
        "x": 6,
        "y": 6,
        "w": 4,
        "h": 3
      }
    ];
    const moved = GridPlacement.anchorPlaces(stack, {
      "cols": 16,
      "rows": 9
    }, {
      "cols": 16,
      "rows": 7
    });
    compare(moved[1].y - moved[0].y, 2, "kept together");
    compare(moved[1].y + moved[1].h, 7, "the stack keeps to the end");
    compare(GridPlacement.touchingGroups([stack[0], null, stack[1],
      {
        "x": 0,
        "y": 0,
        "w": 1,
        "h": 1
      }
    ]), [[0, 2], [3]]);
    compare(GridPlacement.touchingGroups([
      {
        "x": 0,
        "y": 0,
        "w": 4,
        "h": 2
      },
      {
        "x": 4,
        "y": 2,
        "w": 8,
        "h": 2
      }
    ]), [[0], [1]], "a corner alone doesn't join");
  }

  // The default lock and login screens on an ultrawide grid: the clock
  // keeps its corner, the centred stack stays centred
  function test_anchorPlaces_default_screens_on_ultrawide() {
    const from = {
      "cols": 16,
      "rows": 9
    };
    const to = {
      "cols": 21,
      "rows": 8
    };
    const place = (x, y, w, h) => ({
          "x": x,
          "y": y,
          "w": w,
          "h": h
        });
    const lock = GridPlacement.anchorPlaces([place(0, 0, 4, 2), place(4, 2, 8, 2), place(5, 4, 6, 1), place(0, 7, 5, 2)], from, to);
    compare([lock[0].x, lock[0].y], [0, 0], "lock screen: the clock in its corner");
    compare(lock[1].x, 7, "the Greeting centred (6.5 rounded)");
    compare([lock[3].x, lock[3].y + lock[3].h], [0, 8], "NowPlaying at the bottom left");
    const greeter = GridPlacement.anchorPlaces([place(0, 0, 4, 2), place(4, 2, 8, 2), place(5, 4, 6, 3), place(6, 7, 4, 1), place(0, 8, 2, 1), place(13, 8, 3, 1)], from, to);
    compare([greeter[0].x, greeter[0].y], [0, 0], "login screen: the clock in its corner");
    compare(greeter[2].x - greeter[1].x, 1, "Login moves with the Greeting");
    compare(greeter[5].x + greeter[5].w, 21, "Power at the right");
  }

  function test_screenArrangement() {
    const from = {
      "cols": 16,
      "rows": 9
    };
    const places = [
      {
        "x": 0,
        "y": 0,
        "w": 5,
        "h": 2
      },
      {
        "x": 11,
        "y": 0,
        "w": 5,
        "h": 2
      }
    ];
    // Card 425 at zoom 1: gap 20, unit 91.25, step 111.25
    const fits = GridPlacement.screenArrangement(places, from, 425, 2560, 1080, 20, false, 1);
    compare([fits.cols, fits.rows, fits.unit, fits.gap, fits.zoom, fits.shrunk], [22, 8, 425, 20, 1, false]);
    compare(fits.places[1].x, 17, "kept to the right edge");
    const zoomed = GridPlacement.screenArrangement(places, from, 425, 2560, 1080, 20, false, 1.2);
    compare([zoomed.gap, zoomed.zoom], [24, 1.2], "content and gaps drawn at its Module size");
    // Big cards: 8 across can't hold both, so the cards shrink until 10
    // across do, and no further, content and gaps with them
    const shrunk = GridPlacement.screenArrangement(places, from, 850, 1920, 1080, 20, false, 1);
    verify(shrunk.shrunk);
    compare(shrunk.cols, 10);
    verify(shrunk.unit < 850 && shrunk.unit > 1080 / 9 * 4 / 2, "smaller, but not back to the old grid");
    fuzzyCompare(shrunk.zoom, shrunk.unit / 850, 0.002, "its content shrinks with it (its unit in whole px)");
    fuzzyCompare(shrunk.gap, 20 * shrunk.zoom, 1e-9);
    compare([shrunk.places[0].x, shrunk.places[1].x], [0, 5]);
    // A double grid: twice the units each way, on half cards
    const fine = GridPlacement.screenArrangement([], {
      "cols": 32,
      "rows": 18
    }, 425, 2560, 1080, 20, true, 1);
    compare([fine.cols, fine.rows, fine.unit, fine.zoom], [44, 16, GridPlacement.fineUnit(425, 20), 1], "22 × 8 whole units");
    // Too big for the room even on its own grid: fitted into it
    const fitted = GridPlacement.screenArrangement([at(0, 0, 4, 4).place], {
      "cols": 16,
      "rows": 9
    }, 850, 800, 450, 20, false, 1);
    verify(fitted.shrunk && fitted.unit < 850);
    fuzzyCompare(fitted.gap / fitted.unit, 20 / 850, 1e-4, "its gaps shrink with its cards");
    // Fitting no smaller grid at all: the grid it was placed on, each
    // count made even upward so nothing moves off it
    const kept = GridPlacement.screenArrangement([at(0, 0, 15, 9).place], {
      "cols": 15,
      "rows": 9
    }, 425, 300, 200, 20, false, 1);
    compare([kept.cols, kept.rows], [16, 10]);
    compare(kept.places[0], at(0, 0, 15, 9).place, "nothing moves");
    // On a double grid, even in whole units: 33 half units reach 17
    // whole, so 18
    const keptFine = GridPlacement.screenArrangement([at(0, 0, 33, 18).place], {
      "cols": 33,
      "rows": 18
    }, 425, 300, 200, 20, true, 1);
    compare([keptFine.cols, keptFine.rows], [36, 20]);
  }

  function test_fitScale() {
    const bounds = {
      "cols": 8,
      "rows": 4
    };
    compare(GridPlacement.fitScale(bounds, 1200, 600, 500), 1, "fits");
    compare(GridPlacement.fitScale(bounds, 510, 600, 500), 0.5, "half as wide as two cards");
    compare(GridPlacement.fitScale({
      "cols": 0,
      "rows": 0
    }, 10, 10, 500), 1, "nothing to fit");
  }

  function test_menuPlacement_and_onScreen() {
    const frame = {
      "startPad": 10,
      "endPad": 10,
      "across": 20,
      "before": 5,
      "after": 8,
      "reserves": true
    };
    const menu = {
      "edge": "right",
      "length": "fit",
      "offset": -1,
      "layout": {
        "modules": [at(0, 0, 2, 4)]
      }
    };
    const place = GridPlacement.menuPlacement(menu, GridPlacement.bounds(menu.layout.modules), 500, frame, 1920, 1080);
    // Two units across (240), four along (500). The edge holds 8 cells
    // from 30 px: centred is cell 2, one before it cell 1, at 160
    compare([place.along, place.across, place.length, place.depth, place.edgeLength], [160, 20, 500, 240, 1080]);
    compare([place.units, place.cell, place.lattice.origin], [4, 1, 30]);
    compare(GridPlacement.menuReservedDepth(place), 268, "across + depth + after");
    frame.reserves = false;
    compare(GridPlacement.menuReservedDepth(place), 5, "a floating menu: what it sits past");
    const onScreen = GridPlacement.menuOnScreen(menu, place, 500);
    // Against the right edge: 1920 - 20 - 240 = 1660
    compare(r4(onScreen.rect), [1652, 152, 256, 516], "the modules plus `after` all round");
    compare(r4(onScreen.modules[0].rect), [1660, 160, 240, 500]);
    menu.length = "edge";
    const whole = GridPlacement.menuOnScreen(menu, GridPlacement.menuPlacement(menu, GridPlacement.bounds(menu.layout.modules), 500, frame, 1920, 1080), 500);
    compare(r4(whole.modules[0].rect), [1660, 10, 240, 1060], "taking the whole edge: stretched along it");
    // An integrated menu always takes its whole edge, its modules from its
    // start: a lone module two units down still spans it
    const integrated = {
      "edge": "right",
      "mode": "integrated",
      "length": "content",
      "offset": -1,
      "layout": {
        "modules": [at(0, 2, 2, 4)]
      }
    };
    const strip = GridPlacement.menuPlacement(integrated, GridPlacement.bounds(integrated.layout.modules), 500, frame, 1920, 1080);
    compare([strip.along, strip.cell], [10, null], "at its edge's start, off the lattice");
    compare(GridPlacement.menuAlong(integrated, 1080, 500, 10, 10), 10);
    compare(r4(GridPlacement.menuOnScreen(integrated, strip, 500).modules[0].rect), [1660, 10, 240, 1060], "stretched end to end");
  }

  function test_menuFillsEdge_and_modules() {
    const menu = (mode, length, edge, modules) => ({
          "mode": mode,
          "length": length,
          "edge": edge,
          "layout": {
            "modules": modules
          }
        });
    compare(GridPlacement.menuFillsEdge(menu("floating", "content", "left", [])), false);
    compare(GridPlacement.menuFillsEdge(menu("floating", "edge", "left", [])), true);
    compare(GridPlacement.menuFillsEdge(menu("integrated", "content", "left", [])), true, "integrated: always");
    compare(GridPlacement.menuKeepsLead(menu("floating", "edge", "left", [])), true, "a whole-edge floating menu keeps its lead");
    compare(GridPlacement.menuKeepsLead(menu("integrated", "edge", "left", [])), false);
    const offset = [at(1, 3, 2, 4), at(0, 7, 2, 2)];
    const side = GridPlacement.menuModules(menu("integrated", "content", "left", offset));
    compare(side.map(module => [module.place.x, module.place.y]), [[1, 0], [0, 4]], "moved up to start at the first, across untouched");
    compare(offset[0].place.y, 3, "the config's own places untouched");
    const top = GridPlacement.menuModules(menu("integrated", "content", "top", [at(2, 1, 4, 4)]));
    compare([top[0].place.x, top[0].place.y], [0, 1], "a top menu: along is x");
    const kept = menu("floating", "edge", "left", offset);
    compare(GridPlacement.menuModules(kept), offset, "a kept lead: as placed");
    compare(GridPlacement.menuModules(menu("floating", "content", "left", offset)), offset, "content length: as placed");
    compare(GridPlacement.menuModules(menu("integrated", "content", "left", [])), [], "none");
  }

  function test_canvasExtent() {
    const bounds = {
      "cols": 2,
      "rows": 6
    };
    const free = GridPlacement.canvasExtent(bounds, null, 1, 3);
    compare([free.leadCols, free.leadRows, free.cols, free.rows], [1, 1, 12, 10], "at least 8 × 4, plus lead and trail");
    const onScreen = GridPlacement.canvasExtent(bounds, {
      "x": -0.5,
      "y": -2,
      "w": 10,
      "h": 4
    }, 1, 3);
    // One unit past the screen all round; a side exactly on a unit adds none
    compare([onScreen.leadCols, onScreen.leadRows, onScreen.cols, onScreen.rows], [2, 3, 13, 10]);
    compare(r4({
      "x": onScreen.view.x,
      "y": onScreen.view.y,
      "width": onScreen.view.w,
      "height": onScreen.view.h
    }), [-1.5, -3, 12, 10], "the view: the screen (and the grid below it) and a unit round, in fractions");
  }

  function test_canvas_geometry() {
    const extent = {
      "leadCols": 1,
      "leadRows": 1,
      "cols": 10,
      "rows": 6,
      "view": {
        "x": -1,
        "y": -1,
        "w": 10,
        "h": 6
      }
    };
    // A step is 130 px at the reference size: 1300 × 780 fits at 0.5
    const fit = GridPlacement.canvasFit(extent, 650, 390, 0.6);
    compare([fit.scale, fit.step, fit.gap, fit.unitSize], [0.5, 65, 10, 55]);
    compare([fit.originX, fit.originY], [70, 70], "centred, a lead unit in (plus half a gap)");
    compare(GridPlacement.canvasFit(extent, 6500, 3900, 0.6).scale, 0.6, "at most maxScale");
    // The screen stays put on the canvas as the grid moves on it
    const screenAt = boxX => {
      const box = {
        "x": boxX,
        "y": -2,
        "w": 10,
        "h": 4
      };
      const at = GridPlacement.canvasScreenRect(GridPlacement.canvasFit(GridPlacement.canvasExtent({
        "cols": 2,
        "rows": 2
      }, box, 1, 3), 650, 390, 0.6), box);
      return r4(at);
    };
    compare(screenAt(-3.5), screenAt(-4), "half a unit along");
    compare(r4(GridPlacement.canvasRect(fit, {
      "x": 1,
      "y": 0,
      "w": 2,
      "h": 1
    })), [135, 70, 120, 55]);
    compare(r4(GridPlacement.canvasScreenRect(fit, {
      "x": 0,
      "y": 0,
      "w": 2,
      "h": 1
    })), [65, 65, 130, 65], "its sides midway in the gaps");
    function drop(x, y, w, h, grab) {
      const p = GridPlacement.canvasDropPlace(fit, x, y, w, h, grab);
      return [p.x, p.y, p.w, p.h];
    }
    compare(drop(70, 70, 1, 1, null), [0, 0, 1, 1]);
    compare(drop(200, 140, 3, 3, null), [1, 0, 3, 3], "a new module held by its middle unit");
    compare(drop(200, 140, 3, 3, {
      "x": 0,
      "y": 0
    }), [2, 1, 3, 3], "a moved one by the unit it was grabbed by");
    compare(drop(200, 140, 3, 3, {
      "x": 500,
      "y": 500
    }), [0, -1, 3, 3], "the grab kept inside the module");
  }

  function test_edgeBand_and_edgeBar() {
    const rect = {
      "x": 10,
      "y": 20,
      "width": 100,
      "height": 50
    };
    compare(r4(GridPlacement.edgeBand(rect, "left", 5)), [10, 20, 5, 50]);
    compare(r4(GridPlacement.edgeBand(rect, "right", 5)), [105, 20, 5, 50]);
    compare(r4(GridPlacement.edgeBand(rect, "top", 5)), [10, 20, 100, 5]);
    compare(r4(GridPlacement.edgeBand(rect, "bottom", 5)), [10, 65, 100, 5]);
    compare(r4(GridPlacement.edgeBand(rect, "", 5)), [0, 0, 0, 0]);
    const span = {
      "x": 30,
      "y": 25,
      "width": 20,
      "height": 10
    };
    compare(r4(GridPlacement.edgeBar(rect, "left", rect, 4)), [8, 20, 4, 50], "the whole side, centred on it");
    compare(r4(GridPlacement.edgeBar(rect, "right", span, 4)), [108, 25, 4, 10], "along the span");
    compare(r4(GridPlacement.edgeBar(rect, "bottom", span, 4)), [30, 68, 20, 4]);
  }

  function test_trackSizes() {
    const natural = GridPlacement.trackSizes({
      "cols": 8,
      "rows": 4
    }, 500);
    compare(natural.unitW, 110);
    compare(natural.unitH, 110);
    compare(natural.width, 1020);
    compare(natural.height, 500);
    const stretched = GridPlacement.trackSizes({
      "cols": 8,
      "rows": 4
    }, 500, {
      "height": 1020
    });
    compare(stretched.unitW, 110, "only the stretched axis grows");
    compare(stretched.unitH, 240);
    compare(stretched.height, 1020);
    const smaller = GridPlacement.trackSizes({
      "cols": 4,
      "rows": 4
    }, 500, {
      "width": 100
    });
    compare(smaller.width, 500, "never below its natural size");
    const fitted = GridPlacement.trackSizes({
      "cols": 8,
      "rows": 4
    }, 500, {
      "height": 380,
      "fit": true
    });
    compare(fitted.unitH, 80, "fit shrinks to the room");
    compare(fitted.height, 380);
    compare(fitted.unitW, 110, "only the fitted axis");
    const floored = GridPlacement.trackSizes({
      "cols": 8,
      "rows": 4
    }, 500, {
      "height": 100,
      "fit": true
    });
    compare(floored.unitH, 55, "fit stops at half a unit");
    compare(GridPlacement.trackSizes({
      "cols": 8,
      "rows": 4
    }, 500, {
      "height": 1020,
      "fit": true
    }).unitH, 240, "fit grows as stretch does");
    compare(GridPlacement.trackSizes({
      "cols": 0,
      "rows": 0
    }, 500).width, 0);
  }

  function test_rectPx() {
    const sizes = GridPlacement.trackSizes({
      "cols": 8,
      "rows": 8
    }, 500);
    compare(GridPlacement.rectPx({
      "x": 4,
      "y": 2,
      "w": 4,
      "h": 6
    }, sizes), {
      "x": 520,
      "y": 260,
      "width": 500,
      "height": 760
    });
  }

  function test_guideFrame() {
    compare(GridPlacement.guideFrame({
      "cols": 12,
      "rows": 8
    }, [p(0, 0, 2, 2)], [0]), p(0, 0, 12, 8), "a bounded grid is the frame");
    compare(GridPlacement.guideFrame(null, [p(0, 0, 6, 2), p(1, 2, 2, 2), p(0, 4, 4, 1)], [1]), p(0, 0, 6, 5), "else the other modules' cover");
    compare(GridPlacement.guideFrame(null, [p(0, 0, 2, 2)], [0]), null, "nothing else, no frame");
    // An edge menu: the screen along its edge, the others across it
    const screen = p(-10.5, -1, 30, 17);
    compare(GridPlacement.guideFrame(null, [p(0, 0, 6, 2), p(1, 2, 2, 4)], [1], screen, "top"), p(-10.5, 0, 30, 2), "a top menu: the screen across, the others down");
    compare(GridPlacement.guideFrame(null, [p(0, 0, 2, 6), p(2, 1, 4, 2)], [1], screen, "left"), p(0, -1, 2, 17), "a side menu: the screen down, the others across");
    compare(GridPlacement.guideFrame(null, [p(3, 0, 2, 2)], [0], screen, "top"), p(-10.5, 0, 30, 2), "alone: its own depth across");
    compare(GridPlacement.guideFrame({
      "cols": 4,
      "rows": 4
    }, [], [], screen, "top"), p(0, 0, 4, 4), "a bounded grid wins");
  }

  function test_alignments() {
    const places = [p(0, 0, 6, 2), p(0, 3, 2, 2), null];
    // Moved to 2, 2 (2 wide): centred under the 6-wide row
    const centred = GridPlacement.alignments(p(2, 2, 2, 2), places, [2], p(0, 0, 6, 5));
    compare(centred.length, 1, "only the centre lines up across");
    compare(centred[0], {
      "axis": "x",
      "kind": "centre",
      "at": 3,
      "from": 0,
      "to": 5,
      "frame": true
    }, "the row's centre and the frame's merge, spanning both");
    // Below the 2 × 2 one, at the same size: every line across matches
    const level = GridPlacement.alignments(p(0, 6, 2, 2), places, [], null);
    compare(level.map(g => g.axis + g.kind + g.at).sort(), ["xcentre1", "xend2", "xstart0"], "a 2-wide one lines up with the other 2-wide one on every line");
    compare(level.find(g => g.kind === "start").from, 0, "the start line runs from the top of the row");
    compare(GridPlacement.alignments(null, places, [], null), []);
  }

  function test_centreGuides() {
    const guides = GridPlacement.centreGuides(p(0, 0, 7, 4));
    compare(guides.map(g => [g.axis, g.at, g.from, g.to]), [["x", 3.5, 0, 4], ["y", 2, 0, 7]]);
    compare(GridPlacement.centreGuides(p(0, 0, 0, 0)), []);
  }

  function test_centredIn() {
    const frame = p(0, 0, 8, 6);
    compare(GridPlacement.centredIn(p(1, 1, 2, 2), frame, "x"), 3);
    compare(GridPlacement.centredIn(p(1, 1, 2, 2), frame, "y"), 2);
    compare(GridPlacement.centredIn(p(1, 1, 3, 2), frame, "x"), null, "an odd difference is half a unit off");
    compare(GridPlacement.centredIn(p(1, 1, 3, 2), p(2, 0, 5, 1), "x"), 3, "in a frame not at 0");
    compare(GridPlacement.centredIn(p(1, 1, 2, 2), null, "x"), null);
    compare(GridPlacement.centredIn(p(0, 0, 3, 1), p(-10.5, 0, 30, 1), "x"), 3, "on a screen box between units, where it lands on one");
    compare(GridPlacement.centredIn(p(0, 0, 2, 1), p(-10.5, 0, 30, 1), "x"), null, "else between units");
  }

  // A canvas with units of 10 px and gaps of 2, unit 0, 0 at 100, 50
  readonly property var guideFit: ({
      "step": 12,
      "gap": 2,
      "unitSize": 10,
      "originX": 100,
      "originY": 50
    })

  function test_canvasGuide() {
    const line = (axis, kind, at) => GridPlacement.canvasGuide(guideFit, {
        "axis": axis,
        "kind": kind,
        "at": at,
        "from": 0,
        "to": 2
      });
    compare(line("x", "start", 1), {
      "x1": 112,
      "y1": 50,
      "x2": 112,
      "y2": 72
    }, "a start on the unit's leading side, over two units");
    compare(line("x", "end", 2).x1, 122, "an end before the gap");
    compare(line("x", "centre", 0.5).x1, 105, "the centre of unit 0");
    compare(line("y", "centre", 1), {
      "x1": 100,
      "y1": 61,
      "x2": 122,
      "y2": 61
    }, "a horizontal one, midway in the gap after unit 0");
  }

  function test_canvasMargins() {
    const margins = GridPlacement.canvasMargins(guideFit, p(2, 0, 2, 1), p(0, 0, 6, 3));
    compare(margins.map(m => [m.side, m.units, m.even]), [["left", 2, true], ["right", 2, true], ["bottom", 2, false]], "no room above isn't shown");
    const left = margins[0];
    compare([left.x1, left.y1, left.x2, left.y2], [100, 55, 124, 55], "from the frame's side to the place's, through its middle");
    compare(margins[1].x2, 170, "to the frame's far side, before its gap");
    compare(GridPlacement.canvasMargins(guideFit, p(0, 0, 1, 1), null), []);
    const onScreen = GridPlacement.canvasMargins(guideFit, p(3, 0, 3, 1), p(-10.5, 0, 30, 1));
    compare(onScreen.map(m => [m.side, m.units, m.exact, m.even]), [["left", 14, false, true], ["right", 14, false, true]], "a screen side between units: rounded, not exact, and even when centred");
  }

  function test_moveTo() {
    const arr = ["a", "b", "c"];
    compare(GridPlacement.moveTo(arr, 0, 2), 1);
    compare(arr, ["b", "a", "c"]);
    compare(GridPlacement.moveTo(arr, 0, 1), -1, "just after itself stays");
    compare(GridPlacement.moveTo(arr, 2, 0), 0);
    compare(arr, ["c", "b", "a"]);
    compare(GridPlacement.moveTo(arr, 7, 0), -1);
  }
}
