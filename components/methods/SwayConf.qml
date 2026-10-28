pragma Singleton
import QtQuick

// Sway commands the shell sends sway itself (SwayManager): quoting, and
// the names of its transforms (docs/dev/compositor/
// sway-backend.md). axiom's config layer is the daemon's
// (internal/compositor/render).
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

  // Sway's output names for Wayland's transforms 0-7
  readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]
}
