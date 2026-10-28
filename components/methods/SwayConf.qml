pragma Singleton
import QtQuick

// Sway commands the shell sends sway itself (SwayManager): the greeter's
// input, and the names of its transforms (docs/dev/compositor/sway-backend.md). axiom's
// config layer is the daemon's (internal/compositor/render).
QtObject {
  id: root

  // A string as one argument of a sway command, arriving as it is from a
  // config file and at runtime alike: bare when it's plain word
  // characters, else each run without a `"` in double quotes and each `"`
  // in single ones. Sway takes unescaped quotes out but keeps a backslash
  // before one, so escaping a quote can't work.
  function quote(text) {
    const value = String(text ?? "");
    if (/^[A-Za-z0-9_.:+\-\/@~=*]+$/.test(value))
      return value;
    return value.split("\"").map(part => part === "" ? "" : `"${part}"`).join("'\"'") || "\"\"";
  }

  // A field's value as its sway command takes it (by its x-compositor.sway
  // `spec`), or null to leave it
  function _swayValue(spec, value) {
    if (spec.skip !== undefined && value === spec.skip)
      return null;
    if (spec.map !== undefined)
      return spec.map[String(value)] ?? null;
    switch (spec.value) {
    case "enabled":
      return value ? "enabled" : "disabled";
    case "yesNo":
      return value ? "yes" : "no";
    case "enableDisable":
      return value ? "enable" : "disable";
    case "raw":
      return String(value);
    }
    if (spec.scale !== undefined)
      return String(Math.round(value * spec.scale * 1000) / 1000);
    return quote(value);
  }

  /**
   * The input (CompositorLayer.input) as sway commands: Input's fields with
   * a sway command (x-compositor.sway's `key`, `{}` for the value), each
   * written when its part is on (else once changed from its default), then
   * the cursor theme. `live`: for sending now, leaving out what sway takes
   * only from a config file (`configOnly`).
   */
  function inputLines(input, inputSchema, live) {
    const lines = [];
    for (const field of CompositorLayer.annotatedFields(inputSchema, input?.values ?? {}, "sway", true)) {
      if (live && field.spec.configOnly)
        continue;
      const value = _swayValue(field.spec, field.value);
      if (value !== null)
        lines.push(field.spec.key.replace("{}", value));
    }
    if (input?.cursor)
      lines.push(cursorLine(input.cursor.xcursor ?? input.cursor.theme, input.cursor.size));
    return lines;
  }

  function cursorLine(theme, size) {
    return `seat * xcursor_theme ${quote(theme)} ${Math.round(size)}`;
  }

  // --- Outputs ---

  // Sway's output names for Wayland's transforms 0-7
  readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]
}
