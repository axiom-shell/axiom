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
}
