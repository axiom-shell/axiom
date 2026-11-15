pragma Singleton
import QtQuick

// Which windows show on an output (its active workspace, and the special
// workspace open over it) and whether one of them is fullscreen. Hyprland
// 0.57 gives a special workspace no id (its windows say -1), so a special
// matches by name where the output gives one, else by id. No files,
// processes or services.
QtObject {
  id: root

  // Whether `win` shows on `output`: on its active workspace or on the
  // special workspace open on it. False for a null output or window
  function onOutput(output, win) {
    if (!output || !win)
      return false;
    if (output.activeWorkspaceId !== -1 && win.workspaceId === output.activeWorkspaceId)
      return true;
    if ((output.specialWorkspaceName ?? "") !== "")
      return win.workspaceName === output.specialWorkspaceName;
    return output.specialWorkspaceId !== 0 && output.specialWorkspaceId !== -1 && win.workspaceId === output.specialWorkspaceId;
  }

  // The windows of `windows` that show on `output` (hidden ones included:
  // callers filter `hidden` themselves)
  function shown(output, windows) {
    return (windows ?? []).filter(w => root.onOutput(output, w));
  }

  // Whether a window showing on `output` is fullscreen (maximized ones
  // don't count: they leave reserved space alone)
  function hasFullscreen(output, windows) {
    return root.shown(output, windows).some(w => w.fullscreen);
  }

  // A string that changes when the output's active or open special
  // workspace does ("5/special:gaming", "5/0")
  function workspaceKey(output) {
    return output.activeWorkspaceId + "/" + (output.specialWorkspaceName || output.specialWorkspaceId);
  }
}
