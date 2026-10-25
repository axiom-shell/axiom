pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Apps section: the apps axiom opens (keybinds, the
// launcher's terminal apps and Shift+Enter commands)
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Apps

  readonly property string terminal: _c.terminal
  // Empty is the system default (xdg-open / xdg-settings)
  readonly property string fileManager: _c.fileManager
  readonly property string browser: _c.browser
  // Desktop entry ids every dock shows first, unless it has its own
  // (DockConfig.pinnedOf). Through a string, like DockConfig.docks
  readonly property string _pinnedJson: JSON.stringify(_c.pinned)
  readonly property var pinned: JSON.parse(_pinnedJson)
  // What a bind (or the onboarder) runs to open each
  readonly property string terminalCommand: terminal.trim() || "xdg-terminal-exec"
  readonly property string fileManagerCommand: fileManager.trim() || 'xdg-open "$HOME"'
  // `argv` run in a terminal: `terminal` (a widget's own), else the Apps
  // one (which may carry arguments of its own), else xdg-terminal-exec,
  // which takes the command without -e
  function inTerminal(argv, terminal) {
    const term = String(terminal ?? "").trim() || root.terminal.trim();
    return term ? ["sh", "-c", term + ' -e "$@"', "sh"].concat(argv) : ["xdg-terminal-exec"].concat(argv);
  }
  readonly property string browserCommand: browser.trim() || 'b=$(xdg-settings get default-web-browser 2>/dev/null) && [ -n "$b" ] && gtk-launch "${b%.desktop}" || xdg-open https://'
}
