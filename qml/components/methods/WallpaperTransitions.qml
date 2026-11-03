pragma Singleton
import QtQuick

// Which transition a wallpaper change plays (WallpaperView): the
// configured one, or one from the pool for "random", with its direction,
// origin and sweep (set, from a click, or random), and its easing. Every
// screen that changes at once picks from the same seed, so they play the
// same one. No file access, processes or services.
QtObject {
  id: root

  // Every transition, by the name of its shader
  // (components/surfaces/wallpaper/shaders/<name>.frag)
  readonly property var names: ["fade", "wipe", "slide", "grow", "shrink", "wave", "dissolve", "pixelate", "blinds", "tiles", "zoom", "ripple", "swirl", "blur", "clock"]
  // Those that move along a direction: any angle, or (picked at random or
  // from a click) only along an axis. Radial's is where its hand starts.
  readonly property var _anyAngle: ["wipe", "wave", "tiles", "clock"]
  readonly property var _axisAngle: ["slide", "blinds"]
  // Those that spread from a point
  readonly property var _fromPoint: ["grow", "shrink", "ripple", "swirl", "zoom", "clock"]
  // Those that happen everywhere at once unless told to sweep: along the
  // direction or out from the point (the shader's `sweep`)
  readonly property var _sweeping: ["fade", "dissolve", "pixelate", "blur"]
  // Appearance.wallpaper.transition.direction: the angle it moves at
  // (radians, y down)
  readonly property var _angles: ({
      "right": 0,
      "downRight": Math.PI / 4,
      "down": Math.PI / 2,
      "downLeft": 3 * Math.PI / 4,
      "left": Math.PI,
      "upLeft": 5 * Math.PI / 4,
      "up": 3 * Math.PI / 2,
      "upRight": 7 * Math.PI / 4
    })
  // Appearance.wallpaper.transition.position: where it starts
  readonly property var _places: ({
      "center": {
        "x": 0.5,
        "y": 0.5
      },
      "topLeft": {
        "x": 0,
        "y": 0
      },
      "topRight": {
        "x": 1,
        "y": 0
      },
      "bottomLeft": {
        "x": 0,
        "y": 1
      },
      "bottomRight": {
        "x": 1,
        "y": 1
      }
    })

  // The Easing.Type for Appearance.wallpaper.transition.easing
  function easing(name) {
    switch (name) {
    case "easeOut":
      return Easing.OutCubic;
    case "easeIn":
      return Easing.InCubic;
    case "linear":
      return Easing.Linear;
    case "snappy":
      return Easing.OutExpo;
    default:
      return Easing.InOutCubic;
    }
  }

  function _snapToAxis(angle) {
    const quarter = Math.PI / 2;
    return (Math.round(angle / quarter) % 4) * quarter;
  }

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
  // "none" switches at once). `options` ({ direction, position, point },
  // the settings and the clicked point { x, y } in screen units or null;
  // left out: all random) aim it:
  // - position "click" with a point: point transitions start there,
  //   moving ones move away from it (along an axis for slide and blinds;
  //   a click near the middle leaves it to the direction), and fade,
  //   dissolve, pixelate and blur spread out from it. Without a point it
  //   is random.
  // - a direction moves it that way (fade and co. sweep along it); a
  //   position starts it there (fade and co. spread from it).
  // - random: any angle (an axis for slide and blinds), the middle, a
  //   corner or anywhere, and fade and co. at once, sweeping or spreading.
  // Returns { name, angle (radians), origin: { x, y } in screen units,
  // sweep (0 at once, 1 along the angle, 2 out from the origin), seed };
  // name "none" for no transition.
  function pick(type, pool, seed, forced, options) {
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
        "sweep": 0,
        "seed": 0
      };
    if (name === "random") {
      const allowed = (pool ?? []).filter(n => root.names.includes(n));
      const from = allowed.length > 0 ? allowed : root.names;
      name = from[Math.min(from.length - 1, Math.floor(next() * from.length))];
    }
    if (!root.names.includes(name))
      name = "fade";
    const direction = root._angles[options?.direction] !== undefined ? options.direction : "random";
    const position = options?.position ?? "random";
    const point = position === "click" && options?.point ? options.point : null;
    const place = root._places[position] ?? null;

    let sweep = 0;
    if (root._sweeping.includes(name)) {
      if (point)
        sweep = 2;
      else if (direction !== "random")
        sweep = 1;
      else if (place)
        sweep = 2;
      else
        sweep = Math.min(2, Math.floor(next() * 3));
    }
    const axis = root._axisAngle.includes(name);
    const moves = axis || root._anyAngle.includes(name) || sweep === 1;
    const spreads = root._fromPoint.includes(name) || sweep === 2;

    let angle = 0;
    if (moves) {
      // Away from the click, toward the middle and past it
      const away = point ? {
        "x": 0.5 - point.x,
        "y": 0.5 - point.y
      } : null;
      if (away && Math.hypot(away.x, away.y) >= 0.05) {
        angle = Math.atan2(away.y, away.x);
        if (angle < 0)
          angle += 2 * Math.PI;
        if (axis)
          angle = root._snapToAxis(angle);
      } else if (direction !== "random")
        angle = root._angles[direction];
      else if (axis)
        angle = Math.floor(next() * 4) * Math.PI / 2;
      else
        angle = next() * 2 * Math.PI;
    }
    let origin = {
      "x": 0.5,
      "y": 0.5
    };
    if (spreads && point)
      origin = {
        "x": point.x,
        "y": point.y
      };
    else if (spreads && place)
      origin = place;
    else if (spreads) {
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
      "sweep": sweep,
      "seed": next()
    };
  }
}
