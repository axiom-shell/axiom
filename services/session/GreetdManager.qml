pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Greetd

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor

// The login itself, in the greeter (greeter.qml): who logs in, into which
// session, and the conversation with greetd (Quickshell's Greetd: PAM
// through greetd's IPC). Only the greeter references it, so the user's
// own shell never connects to greetd; its preview leaves every action
// inert. Also the greeter's compositor (sway, else Hyprland): the monitor
// layouts and the input options the bundle carries, and the keyboard
// layout switch.
QtObject {
  id: root

  readonly property bool available: Greetd.available

  // --- Users and sessions ---

  // Regular accounts (GreeterUsers), by name
  readonly property var users: _users
  property var _users: []
  // Wayland sessions (GreeterSessions), by name
  readonly property var sessions: _sessions
  property var _sessions: []

  // Who logs in ({ name, realName, … }, a typed name included), or null
  readonly property var selectedUser: _selectedUser
  property var _selectedUser: null
  // The session they log into, or null while there are none
  readonly property var selectedSession: _sessions.find(session => session.id === root._selectedSessionId) ?? _sessions[0] ?? null
  property string _selectedSessionId: ""

  // A user's picture (AccountsService's icon), or "" when they have none
  function avatarOf(name) {
    return root._avatars.includes(name) ? "file:///var/lib/AccountsService/icons/" + name : "";
  }
  property var _avatars: []

  function selectUser(name) {
    const user = GreeterUsers.find(root._users, name);
    if (user?.name === root._selectedUser?.name)
      return;
    root.cancel();
    root._selectedUser = user;
    // Their last session, if any. Taken even before the sessions are read
    // (the remembered user is selected at start, while they're still being
    // listed): selectedSession falls back to the first while it's unknown
    const last = user ? root._saved.sessions?.[user.name] : undefined;
    if (last)
      root._selectedSessionId = last;
  }

  function selectSession(id) {
    root._selectedSessionId = id;
  }

  // --- The login ---

  // greetd's current question ("Password:", a one-time code), and whether
  // its answer may show as typed
  readonly property string prompt: _prompt
  property string _prompt: ""
  readonly property bool promptEcho: _promptEcho
  property bool _promptEcho: false
  // What the login checks last said (an info line, a failure)
  readonly property string message: _message
  property bool _messageIsError: false
  readonly property bool messageIsError: _messageIsError
  property string _message: ""
  // Waiting on greetd
  readonly property bool busy: _busy
  property bool _busy: false

  signal failed

  // An answer to the current question: the password, at first. Starts a
  // greetd session for the selected user if none is going
  function submit(response) {
    if (!root._selectedUser || root._busy)
      return;
    if (!root.selectedSession) {
      root._message = I18n.tr("No session to start: no wayland-sessions folder lists one");
      root._messageIsError = true;
      root.failed();
      return;
    }
    root._message = "";
    if (Greetd.state === GreetdState.Inactive) {
      root._pending = response;
      root._busy = true;
      Greetd.createSession(root._selectedUser.name);
      return;
    }
    root._busy = true;
    Greetd.respond(response);
  }

  // Drops a session in progress (the user changed, Escape)
  function cancel() {
    root._pending = null;
    root._prompt = "";
    root._busy = false;
    if (Greetd.state !== GreetdState.Inactive)
      Greetd.cancelSession();
  }

  // The answer waiting for greetd's first question
  property var _pending: null

  property Connections _greetd: Connections {
    target: Greetd

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      if (responseRequired && root._pending !== null) {
        const response = root._pending;
        root._pending = null;
        Greetd.respond(response);
        return;
      }
      root._busy = false;
      if (responseRequired) {
        // A further question (a one-time code): asked in the field
        root._prompt = message;
        root._promptEcho = echoResponse;
      } else {
        root._message = message;
        root._messageIsError = error;
      }
    }

    function onAuthFailure(message) {
      root._pending = null;
      root._prompt = "";
      root._busy = false;
      root._message = message || I18n.tr("Wrong password");
      root._messageIsError = true;
      if (Greetd.state !== GreetdState.Inactive)
        Greetd.cancelSession();
      root.failed();
    }

    function onError(error) {
      console.warn("[GreetdManager] greetd:", error);
      root._pending = null;
      root._prompt = "";
      root._busy = false;
      root._message = error;
      root._messageIsError = true;
      root.failed();
    }

    function onReadyToLaunch() {
      const session = root.selectedSession;
      root._remember(root._selectedUser.name, session.id);
      console.log("[GreetdManager] Starting", session.id, "for", root._selectedUser.name);
      Greetd.launch(session.exec, GreeterSessions.environment(session), true);
    }
  }

  // --- Power ---

  // "suspend" | "reboot" | "poweroff": logind lets the greeter's own
  // session do these
  function power(action) {
    if (["suspend", "reboot", "poweroff"].includes(action))
      Quickshell.execDetached(["systemctl", action]);
  }

  // --- Keyboard layouts ---

  // The keyboard's layouts ("us,de" split) and the active one's name
  readonly property var layouts: _layouts
  property var _layouts: []
  readonly property string activeLayout: _activeLayout
  property string _activeLayout: ""

  function nextLayout() {
    CompositorManager.cycleKeyboardLayout("next", () => root._readLayouts());
  }

  function _readLayouts() {
    CompositorManager.withKeyboard(keyboard => {
      root._layouts = keyboard?.layouts ?? [];
      root._activeLayout = keyboard?.keymap ?? "";
    });
  }

  // --- Remembered choices (the greeter's own state) ---

  property var _state: StateManager.createStateHandler("greeter")
  // { lastUser, sessions: { user: session id } }
  property var _saved: ({})

  function _remember(user, session) {
    const sessions = Object.assign({}, root._saved.sessions ?? {});
    sessions[user] = session;
    root._saved = {
      "lastUser": GreeterConfig.rememberUser ? user : "",
      "sessions": sessions
    };
    root._state.save(root._saved);
  }

  // --- Startup ---

  // Each data dir's wayland-sessions/, in lookup order (find lists them
  // in that order, and says nothing of one that isn't there on stdout)
  function _readSessions() {
    const folders = Paths.dataSearchDirs.map(dir => dir + "/wayland-sessions");
    CommandManager.run(["find"].concat(folders, ["-maxdepth", "1", "-name", "*.desktop"]), (exitCode, out) => {
      const files = GreeterSessions.files(out.split("\n").filter(file => file !== ""));
      root._sessions = GreeterSessions.sorted(files.map(entry => GreeterSessions.parse(FileManager.read("file://" + entry.file), entry.id)));
      if (root._sessions.length === 0)
        console.warn("[GreetdManager] No sessions in", folders.join(", "));
    });
  }

  // The monitors and the bundle's input, on the greeter's compositor (sway,
  // else Hyprland: greeter-session.sh)
  function _applyCompositor() {
    const config = ConfigManager.config;
    const inputSchema = ConfigManager.configSchema.properties.Input;
    if (CompositorManager.kind === "hyprland") {
      // Its Lua picks the monitor profile again on each hotplug
      const lua = HyprLua.greeterLua(config.Monitors.profiles, inputSchema, config.Input, name => CompositorLayer.hex(Theme.resolveColor(name)));
      HyprlandManager.runLua(lua.join("\n"));
      const cursor = CompositorLayer.input(config.Input).cursor;
      if (cursor)
        HyprlandManager.setCursor(cursor.theme, cursor.size);
      return;
    }
    // The saved profile for what's connected at start
    CompositorManager.withOutputDetails(outputs => {
      const rules = MonitorLayout.savedRules(config.Monitors.profiles, outputs ?? []);
      if (rules.length > 0)
        CompositorManager.applyOutputs(rules, outputs);
    });
    CompositorManager.applyInput(CompositorLayer.input(config.Input), inputSchema);
  }

  Component.onCompleted: {
    if (!Paths.greeter)
      return;
    root._saved = root._state.load({});
    root._users = GreeterUsers.parse(FileManager.read("file:///etc/passwd"), GreeterUsers.uidRange(FileManager.read("file:///etc/login.defs")));
    if (GreeterConfig.rememberUser && root._saved.lastUser)
      root.selectUser(root._saved.lastUser);
    root._readSessions();
    CommandManager.run(["ls", "-1", "/var/lib/AccountsService/icons"], (exitCode, out) => root._avatars = out.split("\n").filter(name => name !== ""));
    // Windowed (looked at from a running session), the compositor is the
    // session's own: left alone
    if (Quickshell.env("AXIOM_GREETER_WINDOWED") !== "1")
      root._applyCompositor();
    root._readLayouts();
  }
}
