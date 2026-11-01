pragma Singleton
import QtQuick

// Where a wallpaper sits on its screen (WallpaperView and the surfaces
// that show it as a plain Image): the fill mode, and the workspace
// parallax's zoom and shift. No file access, processes or services.
QtObject {
  id: root

  // The image's rect on a screen, in screen units (the screen is 0-1 both
  // ways): { x, y, width, height }, all 0 for an image not loaded.
  // `fill`: "crop" covers the screen, "fit" shows it whole, "stretch"
  // covers it unevenly, "center" at its own size. `zoom` (>= 1) enlarges
  // it for the parallax, and `shiftX` / `shiftY` (-1 to 1) slide it within
  // what overflows: -1 to its left or top edge, 1 its right or bottom.
  function rect(fill, imageWidth, imageHeight, screenWidth, screenHeight, zoom, shiftX, shiftY) {
    if (!(imageWidth > 0 && imageHeight > 0 && screenWidth > 0 && screenHeight > 0))
      return {
        "x": 0,
        "y": 0,
        "width": 0,
        "height": 0
      };
    const z = Math.max(1, zoom || 1);
    let width = 1;
    let height = 1;
    if (fill !== "stretch") {
      const scale = fill === "fit" ? Math.min(screenWidth / imageWidth, screenHeight / imageHeight) : fill === "center" ? 1 : Math.max(screenWidth / imageWidth, screenHeight / imageHeight);
      width = imageWidth * scale / screenWidth;
      height = imageHeight * scale / screenHeight;
    }
    width *= z;
    height *= z;
    const clamp = v => Math.max(-1, Math.min(1, v || 0));
    return {
      "x": (1 - width) / 2 * (1 + clamp(shiftX)),
      "y": (1 - height) / 2 * (1 + clamp(shiftY)),
      "width": width,
      "height": height
    };
  }

  // The size to decode an image at for a screen ({ width, height }), or
  // null for its own size ("center", or no screen yet). Crop and fit
  // decode just big enough to cover or fit it, zoomed for the parallax.
  function decodeSize(fill, screenWidth, screenHeight, zoom) {
    if (fill === "center" || !(screenWidth > 0 && screenHeight > 0))
      return null;
    const z = Math.max(1, zoom || 1);
    return {
      "width": Math.ceil(screenWidth * z),
      "height": Math.ceil(screenHeight * z)
    };
  }

  // The Image fillMode that draws `fill` the same way
  function fillMode(fill) {
    switch (fill) {
    case "fit":
      return Image.PreserveAspectFit;
    case "stretch":
      return Image.Stretch;
    case "center":
      return Image.Pad;
    default:
      return Image.PreserveAspectCrop;
    }
  }

  // The parallax shift for workspace `index` of `count` (from 0): -1 at
  // the first, 1 at the last, 0 for a lone one or an unknown index
  function parallaxShift(index, count) {
    if (!(count > 1) || !(index >= 0))
      return 0;
    return Math.max(-1, Math.min(1, index / (count - 1) * 2 - 1));
  }

  // The parallax shift { x, y } of an output showing workspace `activeId`.
  // `spec`: { grid, columns, rows (the grid layout's), base (the output's
  // first id), size (its count of ids), dynamic (the compositor keeps the
  // list itself: `ids`, the output's workspace ids in its order), vertical
  // (its workspaces stack top to bottom), still (false where the wallpaper
  // slides away with each workspace, so following them shows nothing),
  // strip ("horizontal" | "vertical" | "": the output's scrolling strip),
  // windows (the active workspace's tiled windows there, { x, y, w, h,
  // focusRank }), width / height (the output's) }.
  // A grid moves both ways, by column and row; the rest along one axis, by
  // place. A strip takes its axis, by how far along it the view is
  // (stripShift); the workspaces' shift on that axis moves to the other
  // one while it's free.
  function parallax(activeId, spec) {
    const none = {
      "x": 0,
      "y": 0
    };
    if (!spec)
      return none;
    const shift = spec.still === false ? none : root._workspaceShift(activeId, spec);
    if (spec.strip !== "horizontal" && spec.strip !== "vertical")
      return shift;
    const vertical = spec.strip === "vertical";
    const along = root.stripShift(spec.windows ?? [], vertical, vertical ? spec.height : spec.width);
    // The workspaces' axis, when it's a single one: by the layout, not the
    // value (a grid's middle row or column shifts 0)
    const theirs = spec.grid ? "" : spec.vertical ? "vertical" : "horizontal";
    if (vertical)
      return {
        "x": theirs === "vertical" ? shift.y : shift.x,
        "y": along
      };
    return {
      "x": along,
      "y": theirs === "horizontal" ? shift.x : shift.y
    };
  }

  // How far along its strip the view is: -1 at its start, 1 at its end, 0
  // while the strip fits on the output (nothing scrolls). `windows` are the
  // strip's ({ x, y, w, h, focusRank }); the view is taken to follow the
  // focused one (the lowest focusRank), as a scrolling layout keeps it in
  // view: niri doesn't say where its view is. Only the windows' places
  // relative to each other count, so a layout reported unscrolled (niri's)
  // and one reported where it shows (Hyprland's) agree.
  function stripShift(windows, vertical, length) {
    if (!(length > 0) || windows.length === 0)
      return 0;
    const from = w => vertical ? w.y : w.x;
    const size = w => vertical ? w.h : w.w;
    let start = Infinity, end = -Infinity, focused = null;
    for (const w of windows) {
      start = Math.min(start, from(w));
      end = Math.max(end, from(w) + size(w));
      if (focused === null || (w.focusRank ?? Infinity) < (focused.focusRank ?? Infinity))
        focused = w;
    }
    const extent = end - start;
    if (extent <= length + 1)
      return 0;
    const center = from(focused) + size(focused) / 2 - start;
    const f = Math.max(0, Math.min(1, (center - length / 2) / (extent - length)));
    return f * 2 - 1;
  }

  // The workspaces' part of the parallax (parallax)
  function _workspaceShift(activeId, spec) {
    const none = {
      "x": 0,
      "y": 0
    };
    if (!Number.isFinite(activeId) || activeId === 0)
      return none;
    if (spec.grid) {
      const index = activeId - spec.base;
      if (index < 0 || index >= spec.columns * spec.rows)
        return none;
      return {
        "x": root.parallaxShift(index % spec.columns, spec.columns),
        "y": root.parallaxShift(Math.floor(index / spec.columns), spec.rows)
      };
    }
    const index = spec.dynamic ? (spec.ids ?? []).indexOf(activeId) : activeId - spec.base;
    const count = spec.dynamic ? (spec.ids ?? []).length : spec.size;
    const shift = root.parallaxShift(index, count);
    return spec.vertical ? {
      "x": 0,
      "y": shift
    } : {
      "x": shift,
      "y": 0
    };
  }
}
