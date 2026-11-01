pragma Singleton
import QtQuick

// Which compositor axiom runs under, from the environment
// (CompositorManager.kind). A variable can outlive its compositor: one
// sway exported into the systemd user environment reaches the niri started
// after it. With more than one set, the one whose process still runs wins.
// No file access, processes or services: the caller says what runs.
QtObject {
  id: root

  // The variables candidates() reads, for the caller to fill `env` from
  readonly property var envNames: ["HYPRLAND_INSTANCE_SIGNATURE", "SWAYSOCK", "NIRI_SOCKET", "XDG_RUNTIME_DIR"]

  // The compositors the environment names, most trusted first:
  // [{ kind, pid, lockFile }]. `env` holds HYPRLAND_INSTANCE_SIGNATURE,
  // SWAYSOCK, NIRI_SOCKET and XDG_RUNTIME_DIR. `pid` comes from the socket's
  // name (sway-ipc.<uid>.<pid>.sock, niri.<display>.<pid>.sock), else "";
  // Hyprland's is in `lockFile` instead (its first line), else "".
  function candidates(env) {
    const list = [];
    const signature = env.HYPRLAND_INSTANCE_SIGNATURE ?? "";
    if (signature !== "")
      list.push({
        "kind": "hyprland",
        "pid": "",
        "lockFile": `${env.XDG_RUNTIME_DIR ?? ""}/hypr/${signature}/hyprland.lock`
      });
    const sway = env.SWAYSOCK ?? "";
    if (sway !== "")
      list.push({
        "kind": "sway",
        "pid": (sway.match(/sway-ipc\.\d+\.(\d+)\.sock$/) ?? [])[1] ?? "",
        "lockFile": ""
      });
    const niri = env.NIRI_SOCKET ?? "";
    if (niri !== "")
      list.push({
        "kind": "niri",
        "pid": (niri.match(/\.(\d+)\.sock$/) ?? [])[1] ?? "",
        "lockFile": ""
      });
    return list;
  }

  // The kind to run under: the only candidate as it is (nothing asked),
  // else the first that `isRunning(candidate)` says runs, else the first;
  // "" with none
  function pick(candidates, isRunning) {
    if (candidates.length === 0)
      return "";
    if (candidates.length === 1)
      return candidates[0].kind;
    return (candidates.find(candidate => isRunning(candidate)) ?? candidates[0]).kind;
  }

  // What tells one run of compositor `kind` from the next: the variable
  // naming its instance (Hyprland's signature, sway's or niri's socket,
  // each new every time it starts) from `env`, "" with none
  function sessionKey(env, kind) {
    const name = ({
        "hyprland": "HYPRLAND_INSTANCE_SIGNATURE",
        "sway": "SWAYSOCK",
        "niri": "NIRI_SOCKET"
      })[kind];
    return name ? String(env[name] ?? "") : "";
  }

  // The pid in a Hyprland lock file's text (its first line), or ""
  function lockPid(text) {
    const line = String(text ?? "").split("\n")[0].trim();
    return /^\d+$/.test(line) ? line : "";
  }

  // Whether a process's /proc/<pid>/comm text (null when it's gone) is
  // the compositor `kind`
  function isProcess(kind, comm) {
    return comm !== null && comm !== undefined && String(comm).trim().toLowerCase() === kind;
  }
}
