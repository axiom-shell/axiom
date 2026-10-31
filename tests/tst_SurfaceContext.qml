import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SurfaceContext"

  // An enriched bar, as far as SurfaceContext reads it
  function bar(background) {
    return {
      "background": background,
      "solid": background === "solid",
      "pills": background === "pills",
      "island": background === "floating" || background === "floatingPills"
    };
  }

  readonly property var surface: ({
      "held": false,
      "detached": false,
      "ownIsland": false,
      "ownEndHeld": false,
      "stroke": 2
    })

  // Every perpendicular edge, border on and off: what an end meets, and
  // what that makes it for an attached surface. One row per intersection,
  // the same for bar popouts, edge popouts, docks and submenus alike.
  function test_endKinds_data() {
    const rows = [];
    const expect = {
      "none": ["border", "bare"],
      "solid": ["border", "solidStroke"],
      "pills": ["pillBar", "pillBar"],
      "transparent": ["wall", "wall"],
      "floating": ["wall", "wall"],
      "floatingPills": ["wall", "wall"]
    };
    for (const background of Object.keys(expect)) {
      [true, false].forEach((border, i) => rows.push({
          "tag": `${background}, border ${border ? "on" : "off"}`,
          "bar": background === "none" ? null : bar(background),
          "border": border,
          "kind": expect[background][i]
        }));
    }
    return rows;
  }
  function test_endKinds(data) {
    const e = SurfaceContext.endKind({
      "border": data.border,
      "bar": data.bar
    });
    compare(e.kind, data.kind);
    compare(e.joinable, data.kind !== "wall");
    const end = SurfaceContext.end(e, surface);
    compare(end.joins, data.kind !== "wall");
    compare(end.wall, data.kind === "wall");
    compare(end.straight, data.kind === "bare");
    compare(end.strokeInset, data.kind === "wall" || data.kind === "bare" ? 0 : 2);
    compare(end.sink, {
      "border": "border",
      "bare": null,
      "solidStroke": "solidBar",
      "pillBar": "pillBar",
      "wall": null
    }[data.kind]);
  }

  function test_menuStripIsAWall() {
    compare(SurfaceContext.endKind({
      "border": true,
      "bar": null,
      "menuZone": 40
    }).kind, "wall");
  }

  function test_hiddenPillBarIsAWall() {
    compare(SurfaceContext.endKind({
      "border": true,
      "bar": bar("pills"),
      "barShowing": false
    }).kind, "wall");
  }

  // Held, detached or on an island, no end joins (each host once gated
  // this differently); only a held surface has no walls (it keeps its
  // gaps), nor an island at a bar its own end is held clear of
  function test_nothingJoins_data() {
    return [
      {
        "tag": "held",
        "s": {
          "held": true
        },
        "wall": false
      },
      {
        "tag": "detached",
        "s": {
          "detached": true
        },
        "wall": true
      },
      {
        "tag": "island",
        "s": {
          "ownIsland": true
        },
        "wall": true
      },
      {
        "tag": "island, end held",
        "s": {
          "ownIsland": true,
          "ownEndHeld": true
        },
        "wall": false
      }
    ];
  }
  function test_nothingJoins(data) {
    const s = Object.assign({}, surface, data.s);
    for (const background of [null, "solid", "pills"]) {
      const end = SurfaceContext.end(SurfaceContext.endKind({
        "border": true,
        "bar": background ? bar(background) : null
      }), s);
      verify(!end.joins, `${background} joins`);
      compare(end.strokeInset, 0);
      compare(end.sink, null);
    }
    const wall = SurfaceContext.end(SurfaceContext.endKind({
      "border": true,
      "bar": bar("transparent")
    }), s);
    compare(wall.wall, data.wall);
  }

  function test_margins() {
    // gap 48, stroke 2, radius 24
    compare(SurfaceContext.filletMargin(false, 2, 24), 23);
    compare(SurfaceContext.filletMargin(true, 2, 24), 0);
    compare(SurfaceContext.filletMargin(false, 4, 1), 0);
    compare(SurfaceContext.endRoom(false, true, 2, 24), 47);
    compare(SurfaceContext.endRoom(false, false, 2, 24), 23);
    compare(SurfaceContext.endRoom(true, false, 2, 24), 0);
    compare(SurfaceContext.wallLine(30, 40, 10), 50);
    compare(SurfaceContext.wallLine(60, 40, 10), 60);
  }

  function test_detached_data() {
    return [
      {
        "tag": "held",
        "held": true,
        "bar": "solid",
        "mode": "plain",
        "detached": true
      },
      {
        "tag": "no bar",
        "held": false,
        "bar": null,
        "mode": "plain",
        "detached": false
      },
      {
        "tag": "solid",
        "held": false,
        "bar": "solid",
        "mode": "plain",
        "detached": false
      },
      {
        "tag": "transparent",
        "held": false,
        "bar": "transparent",
        "mode": "plain",
        "detached": true
      },
      {
        "tag": "pills",
        "held": false,
        "bar": "pills",
        "mode": "pill",
        "detached": false
      },
      {
        "tag": "pills, none showing",
        "held": false,
        "bar": "pills",
        "mode": "merged",
        "detached": false
      },
      {
        "tag": "island",
        "held": false,
        "bar": "floating",
        "mode": "island",
        "detached": false
      },
      {
        "tag": "floating, between islands",
        "held": false,
        "bar": "floating",
        "mode": "between",
        "detached": false
      },
      {
        "tag": "floating, no islands",
        "held": false,
        "bar": "floating",
        "mode": "plain",
        "detached": true
      }
    ];
  }
  function test_detached(data) {
    compare(SurfaceContext.detached(data.held, data.bar ? bar(data.bar) : null, data.mode), data.detached);
  }

  // A surface's shadow is what it grows out of: joined shapes then land in
  // one group and cast one shadow round them
  function test_shadow_data() {
    return [
      {
        "tag": "border",
        "s": {
          "bar": null,
          "onBar": false
        },
        "look": "style"
      },
      {
        "tag": "bare edge",
        "s": {
          "bar": null,
          "onBar": false
        },
        "look": "style"
      },
      {
        "tag": "solid bar under the border",
        "s": {
          "bar": bar("solid"),
          "onBar": false
        },
        "look": "style"
      },
      {
        "tag": "pills, border on",
        "s": {
          "bar": bar("pills"),
          "onBar": true
        },
        "look": "bar"
      },
      {
        "tag": "pills, border off",
        "s": {
          "bar": bar("pills"),
          "onBar": true
        },
        "look": "bar"
      },
      {
        "tag": "island, border on",
        "s": {
          "bar": bar("floating"),
          "onBar": true
        },
        "look": "bar"
      },
      {
        "tag": "detached",
        "s": {
          "bar": bar("transparent"),
          "onBar": false,
          "detached": true
        },
        "look": "style"
      }
    ];
  }
  function test_shadow(data) {
    const s = SurfaceContext.shadow(Object.assign({
      "detached": false
    }, data.s));
    compare(s, {
      "look": data.look
    });
  }

  function test_submenuTakesItsParentsShadow() {
    const parent = SurfaceContext.shadow({
      "detached": false,
      "bar": null,
      "onBar": false
    });
    compare(SurfaceContext.shadow({
      "parent": parent
    }), parent);
  }

  function test_opening() {
    compare(SurfaceContext.opening(10.4, 50.6), {
      "start": 11,
      "end": 50
    });
    compare(SurfaceContext.opening(0, 10.5, 0, 24), {
      "start": 0,
      "end": 10,
      "endFillet": 10
    });
    // One at each end (a surface standing on the stroke), sharing the room
    compare(SurfaceContext.opening(0.5, 100, 22.5, 22.5), {
      "start": 1,
      "end": 100,
      "startFillet": 22.5,
      "endFillet": 22.5
    });
    compare(SurfaceContext.opening(0, 30, 24, 24), {
      "start": 0,
      "end": 30,
      "startFillet": 24,
      "endFillet": 6
    });
    compare(SurfaceContext.opening(5.5, 5.2).end, 6);
  }

  // ---- frame() / layout(): one surface on an edge, any host ----

  // A 1000 px edge, border on (2 px stroke, radius 12, gap 24), the
  // perpendicular edges' inner sides 20 px in, windows starting there
  function side(kind, extra) {
    return Object.assign({
      "kind": SurfaceContext.endKind({
        "border": true,
        "bar": kind === "none" ? null : bar(kind)
      }),
      "frame": 20,
      "reserved": 20,
      "gapsOut": 10,
      "barHeld": false
    }, extra ?? {});
  }
  function params(extra) {
    return Object.assign({
      "edge": 0,
      "span": 1000,
      "border": true,
      "bareEdge": false,
      "gap": 24,
      "stroke": 2,
      "radius": 12,
      "held": false,
      "gaps": null,
      "bar": null,
      "barStart": 0,
      "barLength": 1000,
      "islandFrom": 0,
      "islandTo": 1000,
      "start": side("none"),
      "end": side("none")
    }, extra ?? {});
  }

  function test_frame_border() {
    const f = SurfaceContext.frame(params());
    const room = SurfaceContext.endRoom(false, true, 2, 12);
    compare(f.lo, 20 + room);
    compare(f.hi, 1000 - 20 - room);
    // Joined ends sit on the strokes' outer edges
    compare(f.joinFrom, 18);
    compare(f.joinTo, 982);
    verify(f.startEnd.joins && f.endEnd.joins);
    compare(f.wallFrom, undefined);
  }

  function test_frame_bare_edges_join_flush() {
    const bare = s => Object.assign(side("none"), {
        "kind": SurfaceContext.endKind({
          "border": false,
          "bar": null
        })
      });
    const f = SurfaceContext.frame(params({
      "border": false,
      "start": bare(),
      "end": bare()
    }));
    compare(f.joinFrom, 20);
    compare(f.joinTo, 980);
    verify(f.startEnd.straight);
  }

  function test_frame_wall_where_windows_start() {
    // A transparent bar on the start side: a wall at its reserved line
    // plus gaps_out, never nearer than its frame line
    const f = SurfaceContext.frame(params({
      "start": side("transparent", {
        "frame": 40,
        "reserved": 34
      })
    }));
    verify(!f.startEnd.joins);
    // The box in line with the windows, its fillet past them
    const fm = SurfaceContext.filletMargin(false, 2, 12);
    compare(f.lo, 44);
    compare(f.wallFrom, 44 - fm);
    // Its window reaches back over the reserved space to hold that fillet
    compare(f.startEnd.strokeInset, Math.ceil(34 - (44 - fm)));
    compare(f.endEnd.strokeInset, 2);
  }

  function test_frame_wall_window_holds_the_fillet() {
    // Windows start just past a transparent bar: the fillet starts over
    // its reserved space, and the window reaches back to it
    const fm = SurfaceContext.filletMargin(false, 2, 12);
    const f = SurfaceContext.frame(params({
      "start": side("transparent", {
        "frame": 60,
        "reserved": 60,
        "gapsOut": 6,
        "corner": 14
      })
    }));
    compare(f.lo, 66);
    compare(f.wallFrom, 66 - fm);
    compare(f.startEnd.strokeInset, 60 - (66 - fm));
  }

  function test_frame_wall_clears_the_frame_corner() {
    // Windows start too near the frame's corner for the fillet to fit
    // beside its arc: the box moves in just far enough, at either end
    const room = SurfaceContext.endRoom(false, true, 2, 12);
    const near = {
      "frame": 24,
      "reserved": 20,
      "corner": 14
    };
    const f = SurfaceContext.frame(params({
      "start": side("transparent", near),
      "end": side("floating", near)
    }));
    compare(f.lo, 14 + room);
    compare(f.hi, 1000 - 14 - room);
    compare(f.wallFrom, 14 + 12);
    compare(f.wallTo, 1000 - 14 - 12);
    // Its fillet starts past where windows start: no reach back
    compare(f.startEnd.strokeInset, 0);
    compare(f.endEnd.strokeInset, 0);
    compare(SurfaceContext.wallAt(30, 14, 22, 34), 26);
    compare(SurfaceContext.wallAt(80, 14, 22, 34), 58);
  }

  function test_frame_held_keeps_its_gaps() {
    const f = SurfaceContext.frame(params({
      "held": true,
      "gaps": {
        "start": 8,
        "end": 0
      },
      "end": side("none", {
        "reserved": 30
      })
    }));
    verify(!f.startEnd.joins && !f.endEnd.joins);
    compare(f.lo, 28);
    // No nearer than where windows start
    compare(f.hi, 970);
  }

  function test_frame_island_bar() {
    const floating = Object.assign(bar("floating"), {
      "extent": 40,
      "pillDepth": 30
    });
    const f = SurfaceContext.frame(params({
      "bar": floating,
      "islandFrom": 30,
      "islandTo": 970,
      // Its end held clear of a bar there: its islands already keep to
      // the windows, so no wall
      "start": side("transparent", {
        "barHeld": true
      })
    }));
    verify(!f.startEnd.joins && !f.endEnd.joins);
    compare(f.wallFrom, undefined);
    const fm = SurfaceContext.filletMargin(false, 2, 12);
    compare(f.lo, 30 + fm);
    compare(f.hi, 970 - fm);
    compare(f.strokeFrom, 30);
  }

  function test_layout_attach_across() {
    const solid = Object.assign(bar("solid"), {
      "extent": 40,
      "innerStroke": true
    });
    const base = params();
    const f = SurfaceContext.frame(base);
    const at = extra => SurfaceContext.layout(f, Object.assign({}, base, {
        "centre": 500,
        "aligned": 450,
        "length": 100,
        "joinStart": false,
        "joinEnd": false,
        "frameLine": 40,
        "reserved": 40
      }, extra));
    // On the stroke of what reserves the edge
    compare(at({}).attachAt, 38);
    compare(at({}).ownSink, "border");
    // Following a solid bar (border off): its own inner stroke
    const onSolid = at({
      "bar": solid,
      "border": false
    });
    compare(onSolid.attachFromBar, 38);
    compare(onSolid.attachAt, 38);
    compare(onSolid.ownSink, "solidBar");
    // Held: a connector gap short of its gap past the frame line
    compare(at({
      "held": true,
      "across": 10
    }).attachAt, 38);
    verify(at({
      "held": true,
      "across": 10
    }).detached);
    // Past a transparent bar: detached, its box (half a connector gap past
    // its attach edge) in line with the windows, even where they start
    // nearer than that half gap past the bar
    const clear = Object.assign(bar("transparent"), {
      "extent": 40,
      "innerStroke": false
    });
    const past = at({
      "bar": clear,
      "detachedPush": 6 - 12
    });
    verify(past.detached);
    compare(past.attachFromBar, 34);
    compare(past.attachAt + 24 / 2, 46);
  }

  // Centred between a pill bar's pills (or a floating bar's islands) and
  // clear of them: grown from the bar's outer edge over the bar, its
  // content starting there, the border's stroke opened under it
  function test_layout_between_pills() {
    const base = params();
    const f = SurfaceContext.frame(base);
    const at = (kind, pills, extra) => SurfaceContext.layout(f, Object.assign({}, base, {
        "bar": Object.assign(bar(kind), {
          "extent": 40,
          "pillDepth": 30,
          "pillMerge": 12
        }),
        "pills": pills,
        "centre": 500,
        "aligned": 450,
        "length": 100,
        "joinStart": false,
        "joinEnd": false,
        "frameLine": 40,
        "reserved": 40
      }, extra ?? {}));
    const apart = [
      {
        "start": 100,
        "length": 200
      },
      {
        "start": 700,
        "length": 200
      }
    ];
    for (const kind of ["pills", "floatingPills"]) {
      const l = at(kind, apart);
      compare(l.mode, "between", kind);
      verify(!l.detached && !l.onPill && !l.merged, kind);
      compare([l.start, l.end, l.stretch], [450, 550, null], kind);
      compare([l.attachFromBar, l.attachClearance, l.attachAt], [0, 0, 0], kind);
      compare(l.ownSink, "border", kind);
      verify(!l.straight, kind);
      // With the border off, straight off the screen edge
      verify(at(kind, apart, {
        "border": false
      }).straight, kind);
    }
    // Too near a pill for two fillets: out of the nearest, as before
    const near = at("pills", [
      {
        "start": 100,
        "length": 200
      },
      {
        "start": 560,
        "length": 200
      }
    ]);
    compare(near.mode, "pill");
    compare(near.pill.index, 1);
  }

  // The plain fill joined between the screen edge and the attach edge,
  // which a host takes off its padding there: the border's margin, or a
  // floating or pill bar's empty depth it grows over; none on anything
  // with content of its own, nor for a box of its own
  function test_layout_attach_fill() {
    const base = params();
    const f = SurfaceContext.frame(base);
    const at = extra => SurfaceContext.layout(f, Object.assign({}, base, {
        "centre": 500,
        "aligned": 450,
        "length": 100,
        "joinStart": false,
        "joinEnd": false,
        "frameLine": 14,
        "reserved": 14
      }, extra));
    compare(at({}).attachFill, 12, "on the border: its margin up to the stroke");
    compare(at({
      "border": false,
      "bareEdge": true,
      "frameLine": 0,
      "reserved": 0
    }).attachFill, 0, "a bare edge: nothing");
    compare(at({
      "menuZone": 60,
      "frameLine": 74,
      "reserved": 74
    }).attachFill, 0, "on an integrated menu");
    compare(at({
      "ownBar": bar("solid"),
      "frameLine": 54,
      "reserved": 54
    }).attachFill, 0, "on a solid bar");
    compare(at({
      "held": true,
      "across": 10
    }).attachFill, 0, "held");
    const pills = kind => Object.assign(bar(kind), {
        "extent": 40,
        "pillDepth": 30,
        "pillMerge": 12
      });
    const floating = {
      "frameLine": 54,
      "reserved": 54
    };
    const between = at(Object.assign({
      "bar": pills("floatingPills"),
      "ownBar": pills("floatingPills"),
      "pills": [
        {
          "start": 100,
          "length": 200
        },
        {
          "start": 700,
          "length": 200
        }
      ]
    }, floating));
    compare(between.mode, "between");
    compare(between.attachFill, between.attachAt, "between pills: up to the bar's outer edge");
    verify(between.attachFill > 0);
    const merged = at(Object.assign({
      "bar": pills("pills"),
      "ownBar": pills("pills"),
      "pills": []
    }, floating));
    verify(merged.merged);
    compare(merged.attachFill, merged.attachAt, "a pill bar showing no pills: the same");
    const onPill = at(Object.assign({
      "bar": pills("pills"),
      "ownBar": pills("pills"),
      "pills": [
        {
          "start": 400,
          "length": 200
        }
      ]
    }, floating));
    verify(onPill.onPill);
    compare(onPill.attachFill, 0, "on a pill");
    const clear = Object.assign(bar("transparent"), {
      "extent": 40,
      "innerStroke": false
    });
    compare(at(Object.assign({
      "bar": clear,
      "ownBar": clear
    }, floating)).attachFill, 0, "detached past a transparent bar");
  }

  // A detached box past a transparent bar slides out from under it, only
  // where layer rules order windows and the overlay isn't open over it
  function test_layout_slides_under() {
    const base = params();
    const f = SurfaceContext.frame(base);
    const at = extra => SurfaceContext.layout(f, Object.assign({}, base, {
        "centre": 500,
        "aligned": 450,
        "length": 100,
        "joinStart": false,
        "joinEnd": false,
        "frameLine": 40,
        "reserved": 40,
        "layerOrder": true,
        "bar": Object.assign(bar("transparent"), {
          "extent": 40
        })
      }, extra));
    verify(at({}).slidesUnder);
    verify(!at({
      "layerOrder": false
    }).slidesUnder);
    verify(!at({
      "overOverlay": true
    }).slidesUnder);
    verify(!at({
      "held": true
    }).slidesUnder);
    verify(!at({
      "bar": Object.assign(bar("solid"), {
        "extent": 40,
        "innerStroke": true
      })
    }).slidesUnder);
    verify(!at({
      "bar": null
    }).slidesUnder);
  }

  // A submenu joined at its parent's bar side, opening toward the end
  // (radius 14, so a fillet and its corner take 28): the parent's island
  // runs 400..600 as its box stretches it, its neighbour 700..900
  function test_submenuJoin_data() {
    const pills = [
      {
        "start": 100,
        "length": 200
      },
      {
        "start": 420,
        "length": 160
      },
      {
        "start": 700,
        "length": 200
      }
    ];
    const own = {
      "index": 1,
      "start": 400,
      "end": 600
    };
    const base = {
      "pills": pills,
      "own": own,
      "radius": 14,
      "stroke": 2,
      "merge": 16,
      "stretchFrom": 0,
      "stretchTo": 1000
    };
    const row = (tag, extra, fillet, end, squareEnd) => ({
          "tag": tag,
          "p": Object.assign({}, base, extra),
          "fillet": fillet,
          "end": end,
          "squareEnd": squareEnd
        });
    return [
      // Short of the neighbour by more than the merge: straight, squared
      row("straight to the wall", {
        "wall": 650
      }, false, 650, true),
      // The wall lands on the neighbour: the fillet and its corner curve
      // into it, the island carried on to merge with it (the 90° corner)
      row("lands on the neighbour", {
        "wall": 750
      }, true, 778, false),
      // Within the merge of the neighbour: it'd merge, so fillet too
      row("within merge of the neighbour", {
        "wall": 690
      }, true, 718, false),
      // Further than the merge, but within the fillet, its corner and the
      // merge: carried on, as a pill bar's joined end is
      // (EdgeAttach.pillJoinFilleted)
      row("within the fillet and merge of the neighbour", {
        "wall": 670
      }, true, 698, false),
      // ...and just past that: straight
      row("past the fillet and merge of the neighbour", {
        "wall": 655
      }, false, 655, true),
      // Near the neighbour's far end: carried on past it for the fillet
      row("past most of the neighbour", {
        "wall": 890
      }, true, 918, false),
      // Its own island already carries on past the wall a little: carried
      // on past the fillet, never a bare T
      row("own island past the wall", {
        "wall": 590
      }, true, 618, false),
      // ...and well past it: the same, inside what it already covers
      row("own island well past the wall", {
        "wall": 500
      }, true, 600, false),
      // No room to grow past the wall: straight at the limit
      row("fillet past the limit", {
        "wall": 750,
        "stretchTo": 760
      }, false, 750, true),
      // Toward the start: mirrored, the first island its neighbour (its
      // start: test_submenuJoin_before_reaches); its end stays put
      row("before: straight", {
        "wall": 350,
        "before": true
      }, false, 600, false), row("before: lands on the neighbour", {
        "wall": 250,
        "before": true
      }, true, 600, false)];
  }

  function test_submenuJoin(data) {
    const j = SurfaceContext.submenuJoin(data.p);
    compare(j.fillet, data.fillet);
    compare(j.stretch.end, data.end);
    compare(j.stretch.squareEnd, data.squareEnd);
    compare(j.stretch.index, 1);
  }

  function test_submenuJoin_before_reaches() {
    const pills = [
      {
        "start": 100,
        "length": 200
      },
      {
        "start": 420,
        "length": 160
      }
    ];
    const p = {
      "pills": pills,
      "own": {
        "index": 1,
        "start": 400,
        "end": 600
      },
      "radius": 14,
      "stroke": 2,
      "merge": 16,
      "stretchFrom": 0,
      "stretchTo": 1000,
      "before": true
    };
    const straight = SurfaceContext.submenuJoin(Object.assign({}, p, {
      "wall": 350
    }));
    compare(straight.stretch.start, 350);
    verify(straight.stretch.squareStart);
    const landed = SurfaceContext.submenuJoin(Object.assign({}, p, {
      "wall": 250
    }));
    compare(landed.stretch.start, 222);
    verify(!landed.stretch.squareStart);
  }

  function test_submenuJoin_off_a_pill() {
    // On the border's or a solid bar's stroke: a fillet where the stroke
    // runs on past it, nothing stretched
    const p = {
      "own": null,
      "radius": 14,
      "stroke": 2,
      "strokeFrom": 0,
      "strokeTo": 1000
    };
    const fits = SurfaceContext.submenuJoin(Object.assign({}, p, {
      "wall": 900
    }));
    verify(fits.fillet);
    compare(fits.stretch, null);
    verify(!SurfaceContext.submenuJoin(Object.assign({}, p, {
      "wall": 990
    })).fillet);
    verify(SurfaceContext.submenuJoin(Object.assign({}, p, {
      "wall": 40,
      "before": true
    })).fillet);
  }

  // A submenu along its parent's side (100..500 at rest; radius 14, so a
  // fillet and the parent's corner take `need`), on a screen 0..1000
  function test_submenuPlace() {
    const need = EdgeAttach.filletMargin(2, 14) + 14;
    const at = extra => SurfaceContext.submenuPlace(Object.assign({
        "attach": {
          "start": 100,
          "length": 400
        },
        "wanted": 200,
        "length": 100,
        "screenFrom": 0,
        "screenTo": 1000,
        "gap": 24,
        "stroke": 2,
        "radius": 14
      }, extra));
    // Level with its item
    compare(at({}).start, 200);
    compare(at({}).end, 300);
    // Near a cornered end, it keeps its fillet clear of the parent's corner
    const cornered = at({
      "wanted": 380
    });
    compare(cornered.end, 500 - need);
    verify(!cornered.flushEnd);
    // Just short of a free end, nudged up to it, running flush (further
    // short, nudged back for its fillet, whichever is nearer)
    const free = at({
      "wanted": 395,
      "freeBottom": true
    });
    compare(free.end, 500);
    verify(free.flushEnd);
    compare(free.grow, 0);
    const back = at({
      "wanted": 380,
      "freeBottom": true
    });
    compare(back.end, 500 - need);
    verify(!back.flushEnd);
    // Joined at the bar side, it reaches the stroke there
    const joined = at({
      "wanted": 110,
      "joinTop": true,
      "joinLine": 60
    });
    verify(joined.joinStart);
    compare(joined.start, 60);
    // Kept on the screen
    compare(at({
      "attach": {
        "start": 800,
        "length": 400
      },
      "wanted": 950
    }).start, 900);
    // Longer than the side, growing up it hangs past the side's top
    const up = at({
      "attach": {
        "start": 600,
        "length": 100
      },
      "wanted": 600,
      "length": 300,
      "growsUp": true
    });
    compare(up.end, 700 - need);
    verify(up.start < 600);
    // With radius 0, at a free end it runs flush, its wall continuing the
    // parent's edge there (not cut short by its backfill)
    const sharp = at({
      "wanted": 100,
      "freeTop": true,
      "radius": 0
    });
    compare(sharp.start, 100);
    verify(sharp.flushStart);
  }
}
