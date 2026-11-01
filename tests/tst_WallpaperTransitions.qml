import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WallpaperTransitions"

  function test_namedTransition() {
    const t = WallpaperTransitions.pick("fade", [], 7, "");
    compare(t.name, "fade");
    compare(t.origin, {
      "x": 0.5,
      "y": 0.5
    }, "fade has no origin");
  }

  function test_none() {
    compare(WallpaperTransitions.pick("none", [], 7, "").name, "none");
    compare(WallpaperTransitions.pick("none", [], 7, "wipe").name, "wipe", "a preview overrides none");
  }

  function test_forced() {
    compare(WallpaperTransitions.pick("random", ["fade"], 3, "ripple").name, "ripple");
    compare(WallpaperTransitions.pick("fade", [], 3, "nonsense").name, "fade", "an unknown preview is ignored");
  }

  function test_unknownType() {
    compare(WallpaperTransitions.pick("sparkle", [], 1, "").name, "fade");
  }

  function test_randomIsDeterministic() {
    for (let seed = 0; seed < 50; seed++)
      compare(WallpaperTransitions.pick("random", [], seed, ""), WallpaperTransitions.pick("random", [], seed, ""), "seed " + seed);
  }

  function test_randomStaysInPool() {
    const pool = ["wipe", "grow", "unknown"];
    const seen = {};
    for (let seed = 0; seed < 200; seed++) {
      const name = WallpaperTransitions.pick("random", pool, seed, "").name;
      verify(name === "wipe" || name === "grow", name);
      seen[name] = true;
    }
    verify(seen.wipe && seen.grow, "both come up");
  }

  function test_randomEmptyPoolUsesAll() {
    const seen = {};
    for (let seed = 0; seed < 500; seed++)
      seen[WallpaperTransitions.pick("random", [], seed, "").name] = true;
    compare(Object.keys(seen).sort(), WallpaperTransitions.names.slice().sort());
  }

  function test_directions() {
    for (let seed = 0; seed < 100; seed++) {
      const slide = WallpaperTransitions.pick("slide", [], seed, "");
      const quarter = slide.angle / (Math.PI / 2);
      fuzzyCompare(quarter, Math.round(quarter), 1e-9, "a slide moves along an axis");
      const wipe = WallpaperTransitions.pick("wipe", [], seed, "");
      verify(wipe.angle >= 0 && wipe.angle < 2 * Math.PI);
      const grow = WallpaperTransitions.pick("grow", [], seed, "");
      verify(grow.origin.x >= 0 && grow.origin.x <= 1 && grow.origin.y >= 0 && grow.origin.y <= 1);
      verify(grow.seed >= 0 && grow.seed < 1);
    }
  }
  function opts(direction, position, point) {
    return {
      "direction": direction,
      "position": position,
      "point": point ?? null
    };
  }

  function test_fixedDirections() {
    const angles = {
      "right": 0,
      "downRight": Math.PI / 4,
      "down": Math.PI / 2,
      "left": Math.PI,
      "up": 3 * Math.PI / 2,
      "upLeft": 5 * Math.PI / 4
    };
    for (const direction in angles)
      for (const name of ["wipe", "slide", "clock", "wave"])
        fuzzyCompare(WallpaperTransitions.pick(name, [], 5, "", opts(direction, "random")).angle, angles[direction], 1e-9, name + " " + direction);
  }

  function test_randomDirectionKeepsAxis() {
    for (let seed = 0; seed < 50; seed++) {
      const angle = WallpaperTransitions.pick("blinds", [], seed, "", opts("random", "random")).angle;
      const quarter = angle / (Math.PI / 2);
      fuzzyCompare(quarter, Math.round(quarter), 1e-9, "seed " + seed);
    }
  }

  function test_clickPoint() {
    const point = {
      "x": 0.1,
      "y": 0.2
    };
    const grow = WallpaperTransitions.pick("grow", [], 9, "", opts("left", "click", point));
    compare(grow.origin, point, "starts at the click");
    const fade = WallpaperTransitions.pick("fade", [], 9, "", opts("left", "click", point));
    compare(fade.sweep, 2, "spreads from the click");
    compare(fade.origin, point);
    const wipe = WallpaperTransitions.pick("wipe", [], 9, "", opts("left", "click", point));
    fuzzyCompare(wipe.angle, Math.atan2(0.3, 0.4), 1e-9, "moves away from the click");
    compare(WallpaperTransitions.pick("slide", [], 9, "", opts("left", "click", point)).angle, 0, "a slide snaps to an axis");
    const middle = {
      "x": 0.5,
      "y": 0.52
    };
    compare(WallpaperTransitions.pick("wipe", [], 9, "", opts("left", "click", middle)).angle, Math.PI, "a click in the middle leaves it to the direction");
  }

  function test_clickWithoutPointIsRandom() {
    for (let seed = 0; seed < 30; seed++)
      for (const name of ["grow", "wipe", "fade", "clock"])
        compare(WallpaperTransitions.pick(name, [], seed, "", opts("random", "click", null)), WallpaperTransitions.pick(name, [], seed, "", opts("random", "random")), name + " seed " + seed);
  }

  function test_fixedPositions() {
    compare(WallpaperTransitions.pick("ripple", [], 2, "", opts("random", "center")).origin, {
      "x": 0.5,
      "y": 0.5
    });
    compare(WallpaperTransitions.pick("zoom", [], 2, "", opts("random", "bottomRight")).origin, {
      "x": 1,
      "y": 1
    });
    const blur = WallpaperTransitions.pick("blur", [], 2, "", opts("random", "topLeft"));
    compare(blur.sweep, 2, "a fixed position spreads from it");
    compare(blur.origin, {
      "x": 0,
      "y": 0
    });
  }

  function test_sweep() {
    const fade = WallpaperTransitions.pick("fade", [], 4, "", opts("up", "topLeft"));
    compare(fade.sweep, 1, "a fixed direction sweeps along it (before a position)");
    fuzzyCompare(fade.angle, 3 * Math.PI / 2, 1e-9);
    compare(WallpaperTransitions.pick("wipe", [], 4, "", opts("up", "random")).sweep, 0, "only fade and co. sweep");
    const seen = {};
    for (let seed = 0; seed < 300; seed++) {
      const t = WallpaperTransitions.pick("dissolve", [], seed, "", opts("random", "random"));
      verify(t.sweep === 0 || t.sweep === 1 || t.sweep === 2, t.sweep);
      compare(t, WallpaperTransitions.pick("dissolve", [], seed, "", opts("random", "random")), "deterministic");
      seen[t.sweep] = true;
    }
    verify(seen[0] && seen[1] && seen[2], "all three come up");
  }

  function test_easing() {
    compare(WallpaperTransitions.easing("smooth"), Easing.InOutCubic);
    compare(WallpaperTransitions.easing("easeOut"), Easing.OutCubic);
    compare(WallpaperTransitions.easing("easeIn"), Easing.InCubic);
    compare(WallpaperTransitions.easing("linear"), Easing.Linear);
    compare(WallpaperTransitions.easing("snappy"), Easing.OutExpo);
    compare(WallpaperTransitions.easing("unknown"), Easing.InOutCubic);
  }
}
