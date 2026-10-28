pragma Singleton
import QtQuick

// What the shell itself hands a compositor's config: a color as hex, and
// a section's settings by their x-compositor annotations (the greeter's
// Hyprland Lua; the daemon's config layer builds its own:
// internal/compositor/render).
QtObject {
  id: root

  // A color ({ r, g, b } in 0-1) as "rrggbb"
  function hex(color) {
    return [color.r, color.g, color.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
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
}
