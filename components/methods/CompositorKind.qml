pragma Singleton
import QtQuick

// Which compositor axiom runs under, from the environment
// (CompositorManager.kind). The daemon starts the shell with only the
// running compositor's variable (ipc.Detect hides one left over from an
// earlier session), so the one set is the one.
// No file access, processes or services: the caller reads the variables.
QtObject {
  id: root

  // The variables each compositor names its instance by, for the caller
  // to fill `env` from
  readonly property var names: ({
      "hyprland": "HYPRLAND_INSTANCE_SIGNATURE",
      "sway": "SWAYSOCK",
      "niri": "NIRI_SOCKET"
    })
  readonly property var envNames: Object.values(root.names)

  // The compositor whose variable `env` has set: "hyprland", "sway",
  // "niri", or "" with none
  function kind(env) {
    return Object.keys(root.names).find(k => String(env[root.names[k]] ?? "") !== "") ?? "";
  }

  // What tells one run of compositor `kind` from the next: the variable
  // naming its instance (Hyprland's signature, sway's or niri's socket,
  // each new every time it starts) from `env`, "" with none
  function sessionKey(env, kind) {
    const name = root.names[kind];
    return name ? String(env[name] ?? "") : "";
  }
}
