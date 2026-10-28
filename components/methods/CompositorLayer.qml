pragma Singleton
import QtQuick

// What axiom asks of the compositor, decided once in a neutral shape: the
// window look and the input that are on, for what the shell itself sets
// (sway's look a window at a time, the cursor, the greeter's compositor;
// the daemon's config layer builds its own: internal/compositor/render).
// Everything read from config, the theme and the shell's look comes in as
// arguments (docs/dev/compositor/contract.md).
QtObject {
  id: root

  // A color ({ r, g, b } in 0-1) as "rrggbb"
  function hex(color) {
    return [color.r, color.g, color.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
  }

  readonly property var lookPartNames: ["borders", "shape", "gaps", "blur", "shadow", "dim", "opacity"]

  /**
   * The window look (WindowLook's values) as the parts that are on:
   *   parts    the names of the parts on, in lookPartNames' order
   *   values   WindowLook's values, for a backend mapping fields by their
   *            schema annotations (x-compositor)
   *   borders  { active, inactive } ("rrggbb"), or null
   *   shape    { width, radius }, or null
   *   gaps     { inner, outer }, or null
   *   blur     { windows, surfaces, size, passes, xray, noise, contrast }:
   *            whether windows blur, and whether axiom's translucent
   *            surfaces do (the compositor's blur stays on for them), and
   *            its strength (noise in ‰, contrast in %), or null
   *   shadow   { size, power, color ("rrggbbaa", or "" for the
   *            compositor's own), rgb ("rrggbb" or ""), alpha (0–1:
   *            baseAlpha × strength, capped), baseAlpha, strength,
   *            offset (px downward), soft (standing in for axiom's own
   *            blurred shadow) }, or null
   *   dim      { strength } in percent, or null
   *   opacity  { active, inactive, fullscreen } in percent, or null
   * `opts`: { activeHex, inactiveHex, borderWidth, radius, surfacesBlur,
   * shadow ({ size, color ("rrggbb" or ""), alpha (0–1), offset, soft,
   * strength (× the alpha; 1 when left out) }, or
   * null for none: axiom's own casting none) }
   */
  // The relative luminance (0–1) of "rrggbb"
  function luminance(hex) {
    const linear = i => {
      const c = parseInt(String(hex).substr(i, 2), 16) / 255;
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    };
    return /^[0-9a-fA-F]{6}/.test(hex) ? 0.2126 * linear(0) + 0.7152 * linear(2) + 0.0722 * linear(4) : 0;
  }

  // 0–1 as two hex digits ("99")
  function alphaHex(alpha) {
    return Math.round(Math.max(0, Math.min(1, alpha)) * 255).toString(16).padStart(2, "0");
  }

  function look(values, opts) {
    const cast = values.shadow.enabled ? opts.shadow : null;
    const clamp = a => Math.max(0, Math.min(1, a));
    const strength = cast ? Math.max(0, cast.strength ?? 1) : 1;
    const alpha = cast ? clamp(cast.alpha * strength) : 0;
    const shadow = cast ? {
      "size": cast.size,
      "power": values.shadow.power,
      "color": cast.color !== "" ? cast.color + alphaHex(alpha) : "",
      "rgb": cast.color,
      "alpha": alpha,
      "baseAlpha": clamp(cast.alpha),
      "strength": strength,
      "offset": cast.offset,
      "soft": cast.soft === true
    } : null;
    return {
      "parts": lookPartNames.filter(part => part === "shadow" ? shadow !== null : values[part]?.enabled === true),
      "values": values,
      "borders": values.borders.enabled ? {
        "active": opts.activeHex,
        "inactive": opts.inactiveHex
      } : null,
      "shape": values.shape.enabled ? {
        "width": opts.borderWidth,
        "radius": opts.radius
      } : null,
      "gaps": values.gaps.enabled ? {
        "inner": values.gaps.inner,
        "outer": values.gaps.outer
      } : null,
      "blur": values.blur.enabled ? {
        "windows": values.blur.windowBlur === true,
        "surfaces": opts.surfacesBlur === true,
        "size": values.blur.size,
        "passes": values.blur.passes,
        "xray": values.blur.xray === true,
        "noise": values.blur.noise,
        "contrast": values.blur.contrast
      } : null,
      "shadow": shadow,
      "dim": values.dim.enabled ? {
        "strength": values.dim.strength
      } : null,
      "opacity": values.opacity.enabled ? {
        "active": values.opacity.active,
        "inactive": values.opacity.inactive,
        "fullscreen": values.opacity.fullscreen
      } : null
    };
  }

  readonly property var inputPartNames: ["keyboard", "mouse", "touchpad", "cursor"]

  /**
   * The input (Input's values) as the parts that are on:
   *   parts    the names of the parts on, in inputPartNames' order
   *   values   Input's values, for a backend mapping fields by their schema
   *            annotations (x-compositor, gated by each part's `enabled`)
   *   cursor   { theme, size, xcursor } while the cursor part is on with a
   *            theme, or null. `xcursor` is the name XCursor readers get
   *            (`xcursorTheme`: CursorThemeManager's companion theme
   *            filling in the standard names the theme lacks), else the
   *            theme's
   */
  function input(values, xcursorTheme) {
    const cursor = values.cursor;
    return {
      "parts": inputPartNames.filter(part => values[part]?.enabled === true),
      "values": values,
      "cursor": cursor.enabled && cursor.theme ? {
        "theme": cursor.theme,
        "size": cursor.size,
        "xcursor": xcursorTheme || cursor.theme
      } : null
    };
  }

  /**
   * A section's settings a compositor's config takes (`objectSchema`, with
   * `values`; inside its groups too), by their annotation
   * x-compositor.<compositor>: [{ name (dotted from the section), schema,
   * value, spec, on }]. `spec` is that compositor's { key, value, scale,
   * if, always, skip, map, configOnly }; `on` whether its `if` switch (a
   * setting beside it, the group's `enabled`) is on, null without one.
   */
  function compositorFields(objectSchema, values, compositor, prefix) {
    const out = [];
    const props = objectSchema?.properties ?? {};
    for (const key in props) {
      const fieldSchema = props[key];
      const value = values?.[key];
      if (value === undefined)
        continue;
      const spec = fieldSchema["x-compositor"]?.[compositor];
      if (spec)
        out.push({
          "name": (prefix ?? "") + key,
          "schema": fieldSchema,
          "value": value,
          "spec": spec,
          "on": spec.if ? values[spec.if] === true : null
        });
      else if (fieldSchema.type === "object" && fieldSchema.properties)
        out.push(...root.compositorFields(fieldSchema, value, compositor, (prefix ?? "") + key + "."));
    }
    return out;
  }

  /**
   * compositorFields, those a config writes: with `gated` (the input)
   * each only while its `if` switch is on, else once changed from its
   * default; without (a managed config's options) every one.
   */
  function annotatedFields(sectionSchema, values, compositor, gated) {
    return root.compositorFields(sectionSchema, values, compositor, "").filter(field => !gated || (field.on !== null ? field.on : field.value !== field.schema.default));
  }
}
