pragma Singleton
import QtQuick

// What the wallpaper is under a rectangle: the grey levels a surface's
// colours are judged against (theme.backdrop's grid, mapped through the
// wallpaper's placement). Grey levels are 0-255 sRGB greys whose WCAG
// luminance is the wallpaper's there. No file access, processes or services.
QtObject {
  id: root

  // A grid from the daemon's answer (`theme.backdrop`: cols, rows, width,
  // height and the base64 byte strings mean, low, high), the bytes as
  // arrays. Once per grid, not per region.
  function decode(result) {
    const bytes = text => root._base64(text ?? "");
    const grid = {
      "cols": result.cols,
      "rows": result.rows,
      "width": result.width,
      "height": result.height,
      "mean": bytes(result.mean),
      "low": bytes(result.low),
      "high": bytes(result.high)
    };
    const cells = grid.cols * grid.rows;
    return cells > 0 && grid.mean.length === cells && grid.low.length === cells && grid.high.length === cells ? grid : null;
  }

  // The grey levels `{ mean, low, high }` under `rect` ({ x, y, width,
  // height }, screen units: the screen is 0-1 both ways), by the cells
  // under it. `imageRect` is where the wallpaper sits on the screen
  // (WallpaperFill.rect, screen units); `travel` ({ x, y }) is the extra
  // share of the screen the wallpaper may still move (parallax, a strip's
  // scroll) in the same units, which widens `rect` by it on each side. `low`
  // is the 10th percentile of the cells' darkest sub-samples and `high` the
  // 90th of their brightest, each cell weighted by how much of the rect it
  // covers; where the rect leaves the image (a letterbox) that part counts as
  // grey level `letterbox`. `blurred` (the compositor blurs what's behind
  // the surface) is the blur weight k: `true` is 1, `false` or undefined 0,
  // a number 0-1 as given. Each cell's low and high move toward its mean by
  // k, in grey levels (Qt's MultiEffect blurs sRGB values). At 1 (64 px)
  // that is the fully averaged model; at partial strength a linear k errs
  // toward too much shade (an estimate, not measured: a small bright patch
  // keeps more of its excess than 1 - k at about 60%).
  function region(grid, imageRect, rect, travel, blurred, letterbox) {
    const tx = travel?.x ?? 0;
    const ty = travel?.y ?? 0;
    const edge = letterbox ?? 0;
    const k = typeof blurred === "number" ? Math.max(0, Math.min(1, blurred)) : blurred ? 1 : 0;
    if (!grid || !(imageRect.width > 0 && imageRect.height > 0))
      return root.flat(edge);
    // The rect in the image's own 0-1 units
    const u0 = (rect.x - tx - imageRect.x) / imageRect.width;
    const u1 = (rect.x + rect.width + tx - imageRect.x) / imageRect.width;
    const v0 = (rect.y - ty - imageRect.y) / imageRect.height;
    const v1 = (rect.y + rect.height + ty - imageRect.y) / imageRect.height;
    const total = Math.max(0, u1 - u0) * Math.max(0, v1 - v0);
    const clamp = v => Math.max(0, Math.min(1, v));
    const cx0 = Math.floor(clamp(u0) * grid.cols);
    const cx1 = Math.min(grid.cols - 1, Math.ceil(clamp(u1) * grid.cols) - 1);
    const cy0 = Math.floor(clamp(v0) * grid.rows);
    const cy1 = Math.min(grid.rows - 1, Math.ceil(clamp(v1) * grid.rows) - 1);
    const means = [];
    const lows = [];
    const highs = [];
    let inside = 0;
    for (let cy = cy0; cy <= cy1; cy++) {
      const wy = Math.min(v1, (cy + 1) / grid.rows) - Math.max(v0, cy / grid.rows);
      for (let cx = cx0; cx <= cx1; cx++) {
        const w = Math.min(u1, (cx + 1) / grid.cols) - Math.max(u0, cx / grid.cols);
        const weight = Math.max(0, w) * Math.max(0, wy);
        if (!(weight > 0))
          continue;
        const i = cy * grid.cols + cx;
        means.push({
          "value": grid.mean[i],
          "weight": weight
        });
        lows.push({
          "value": Math.round(grid.low[i] + (grid.mean[i] - grid.low[i]) * k),
          "weight": weight
        });
        highs.push({
          "value": Math.round(grid.high[i] + (grid.mean[i] - grid.high[i]) * k),
          "weight": weight
        });
        inside += weight;
      }
    }
    // What of the rect lies off the image: the theme background there
    const off = total - inside;
    if (off > 1e-9 * Math.max(total, 1e-12)) {
      for (const list of [means, lows, highs])
        list.push({
          "value": edge,
          "weight": off
        });
    }
    if (means.length === 0)
      return root.flat(edge);
    return {
      "mean": root._meanOf(means),
      "low": root._percentile(lows, 0.1),
      "high": root._percentile(highs, 0.9)
    };
  }

  // What a layout's shade preset allows a bare module's shade: `{ shown,
  // minContrast, maxAlpha }`. Strong is the readable case (the text's
  // contrast over the worst back, whole alpha range); Medium caps the alpha
  // at 0.8, which still gives about 5.6-6.4:1 for the theme's own text over
  // the worst-case pole (gruvbox dark and light), less for a user-picked
  // mid-tone ink; Light is a hint of shade; Off draws none. An unknown
  // preset takes Strong.
  readonly property var _shades: ({
      "off": {
        "shown": false,
        "minContrast": 0,
        "maxAlpha": 0
      },
      "light": {
        "shown": true,
        "minContrast": 3.0,
        "maxAlpha": 0.5
      },
      "medium": {
        "shown": true,
        "minContrast": Tone.textContrast,
        "maxAlpha": 0.8
      },
      "strong": {
        "shown": true,
        "minContrast": Tone.textContrast,
        "maxAlpha": 1
      }
    })

  function shade(preset) {
    const row = root._shades[preset];
    return row ?? root._shades.strong;
  }

  // The shade's alpha: the least that reads (`floor`, Tone.alphaFloor),
  // capped by the preset `look` (Backdrop.shade); 0 when it is not shown
  function shadeAlpha(look, floor) {
    return look.shown ? Math.min(look.maxAlpha, floor) : 0;
  }

  // A region of one colour: a flat backdrop (a screen layout's colour), its
  // three grey levels that colour's
  function flat(color) {
    const g = typeof color === "number" ? color : root.greyOf(color);
    return {
      "mean": g,
      "low": g,
      "high": g
    };
  }

  // The grey level (0-255) whose luminance is `color`'s
  function greyOf(color) {
    return root._grey(Tone.luminance(color));
  }

  // The backs a region gives a surface: `[mean, low, high]` as opaque
  // colours, each `fill` at `alpha` drawn over that grey (alpha 0: the grey
  // itself, a bare backdrop)
  function backs(region, fill, alpha) {
    const top = alpha > 0 ? Tone.alpha(fill, alpha) : null;
    return [region.mean, region.low, region.high].map(g => {
      const grey = Qt.rgba(g / 255, g / 255, g / 255, 1);
      return top ? Tone.over(top, grey) : grey;
    });
  }

  // The band a bar covers along its screen `edge` ("top" | "bottom" |
  // "left" | "right"): the whole length of the edge, `thickness` plus
  // `margin` px deep, as a rect in screen units (`screenSize`: { width,
  // height } px)
  function band(edge, thickness, margin, screenSize) {
    const depth = Math.max(0, thickness + margin);
    const w = Math.max(1, screenSize.width);
    const h = Math.max(1, screenSize.height);
    const across = Math.min(1, depth / (edge === "left" || edge === "right" ? w : h));
    switch (edge) {
    case "bottom":
      return {
        "x": 0,
        "y": 1 - across,
        "width": 1,
        "height": across
      };
    case "left":
      return {
        "x": 0,
        "y": 0,
        "width": across,
        "height": 1
      };
    case "right":
      return {
        "x": 1 - across,
        "y": 0,
        "width": across,
        "height": 1
      };
    default:
      return {
        "x": 0,
        "y": 0,
        "width": 1,
        "height": across
      };
    }
  }

  // The bytes of a base64 string (standard alphabet; Qt.atob's string form is
  // deprecated, and its array form differs between Qt versions)
  function _base64(text) {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const out = [];
    let bits = 0;
    let acc = 0;
    for (let i = 0; i < text.length; i++) {
      const v = alphabet.indexOf(text[i]);
      if (v < 0)
        continue;
      acc = (acc << 6) | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((acc >> bits) & 255);
        acc &= (1 << bits) - 1;
      }
    }
    return out;
  }

  // -- grey and luminance --

  function _lum(grey) {
    const v = grey / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  }

  function _grey(lum) {
    const l = Math.max(0, Math.min(1, lum));
    return Math.round((l <= 0.0031308 ? l * 12.92 : 1.055 * l ** (1 / 2.4) - 0.055) * 255);
  }

  // The mean of weighted grey levels, taken in linear light
  function _meanOf(entries) {
    let sum = 0;
    let weight = 0;
    for (const e of entries) {
      sum += root._lum(e.value) * e.weight;
      weight += e.weight;
    }
    return root._grey(sum / weight);
  }

  // The weighted `p` percentile (0-1) of grey levels: the least level at or
  // below which `p` of the weight lies
  function _percentile(entries, p) {
    const sorted = entries.slice().sort((a, b) => a.value - b.value);
    const total = sorted.reduce((sum, e) => sum + e.weight, 0);
    let seen = 0;
    for (const e of sorted) {
      seen += e.weight;
      if (seen >= p * total - 1e-12)
        return e.value;
    }
    return sorted[sorted.length - 1].value;
  }
}
