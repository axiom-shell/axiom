pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Apps section: the apps axiom opens (keybinds, the
// launcher's terminal apps and Shift+Enter commands, the network
// editor)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Apps

  // Commands axiom starts in place of a default app (Settings › Default
  // apps › Custom command…), by role id ("browser", "terminal", …: the
  // roles DefaultAppsManager.roleList shows): "" uses the default app.
  // Through a string, like pinned
  readonly property string _commandsJson: JSON.stringify(_c.commands)
  readonly property var commands: JSON.parse(_commandsJson)
  // The connection editor the Wi-Fi menu and VPN module open ("" hides
  // their buttons)
  readonly property string networkEditor: _c.networkEditor
  // Desktop entry ids every dock shows first, unless it has its own
  // (DockConfig.pinnedOf). Through a string, like DockConfig.docks
  readonly property string _pinnedJson: JSON.stringify(_c.pinned)
  readonly property var pinned: JSON.parse(_pinnedJson)
  // What a bind (or the onboarder) runs to open each: `axiom open`, which
  // starts the command above or else the default app when the key is
  // pressed, so a new default needs no new compositor config. Binds call
  // the installed binary (Paths.shellCommand), which in dev mode is the
  // install tree's and may predate `open`: the freedesktop opener then
  // starts the default app instead
  readonly property string terminalCommand: `${Paths.shellCommand} open terminal || exec xdg-terminal-exec`
  readonly property string fileManagerCommand: `${Paths.shellCommand} open fileManager "$HOME" || exec xdg-open "$HOME"`
  readonly property string browserCommand: `${Paths.shellCommand} open browser || exec xdg-open https://`
  // `argv` run in a terminal: `terminal` (a widget's own, which may carry
  // arguments of its own) as `terminal -e argv`, else the terminal
  // `axiom open` starts (commands.terminal, else the default terminal),
  // by the binary the daemon runs now (Paths.toolBin: the one the shell
  // was built against, a dev build's in dev mode)
  function inTerminal(argv, terminal) {
    const term = String(terminal ?? "").trim();
    return term ? ["sh", "-c", term + ' -e "$@"', "sh"].concat(argv) : [Paths.toolBin, "open", "terminal", "--"].concat(argv);
  }
}
