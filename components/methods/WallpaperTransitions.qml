pragma Singleton
import QtQuick

// Which transition a wallpaper change plays (WallpaperView): the
// configured one, or one from the pool for "random", with its direction and
// origin. Every screen that changes at once picks from the same seed, so
// they play the same one. No file access, processes or services.
QtObject {
  id: root

  // Every transition, by the name of its shader
  // (components/surfaces/wallpaper/shaders/<name>.frag)
  readonly property var names: ["fade", "wipe", "slide", "grow", "shrink", "wave", "dissolve", "pixelate", "blinds", "checker", "zoom", "ripple", "swirl", "blur"]
  // Those that move along a direction: any angle, or only along an axis
  readonly property var _anyAngle: ["wipe", "wave", "checker"]
  readonly property var _axisAngle: ["slide", "blinds"]
  // Those that spread from a point
  readonly property var _fromPoint: ["grow", "shrink", "ripple", "swirl"]

  // A generator of numbers in [0, 1) from an integer seed (mulberry32)
  function _random(seed) {
    let state = (Math.floor(seed) | 0) >>> 0;
    return () => {
      state = (state + 0x6D2B79F5) | 0;
      let t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // The transition for a change: `forced` (a preview) when it names one,
  // else `type` ("random" picks one of `pool`, all when it names none;
  // "none" switches at once). Returns { name, angle (radians), origin:
  // { x, y } in screen units, seed }; name "none" for no transition.
  function pick(type, pool, seed, forced) {
    const next = root._random(seed);
    let name = root.names.includes(forced) ? forced : type;
    if (name === "none")
      return {
        "name": "none",
        "angle": 0,
        "origin": {
          "x": 0.5,
          "y": 0.5
        },
        "seed": 0
      };
    if (name === "random") {
      const allowed = (pool ?? []).filter(n => root.names.includes(n));
      const from = allowed.length > 0 ? allowed : root.names;
      name = from[Math.min(from.length - 1, Math.floor(next() * from.length))];
    }
    if (!root.names.includes(name))
      name = "fade";
    let angle = 0;
    if (root._anyAngle.includes(name))
      angle = next() * 2 * Math.PI;
    else if (root._axisAngle.includes(name))
      angle = Math.floor(next() * 4) * Math.PI / 2;
    let origin = {
      "x": 0.5,
      "y": 0.5
    };
    if (root._fromPoint.includes(name)) {
      // The middle half the time, else a corner or anywhere
      const where = next();
      if (where >= 0.5 && where < 0.75) {
        const corner = Math.floor(next() * 4);
        origin = {
          "x": corner % 2,
          "y": Math.floor(corner / 2)
        };
      } else if (where >= 0.75) {
        origin = {
          "x": 0.15 + next() * 0.7,
          "y": 0.15 + next() * 0.7
        };
      }
    }
    return {
      "name": name,
      "angle": angle,
      "origin": origin,
      "seed": next()
    };
  }
}
