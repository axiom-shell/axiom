pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.config
import qs.components.methods

/**
 * One streaming chat request, sent with curl. Not a singleton: ChatManager
 * makes one per reply (and one per settings-card test).
 *
 * The API key never reaches argv (readable by any local user in
 * /proc/<pid>/cmdline) or the disk: curl reads its config, headers
 * included, from stdin (`-K -`). The request body, which can hold images
 * too big for argv, goes to a file in $XDG_RUNTIME_DIR (the user's own
 * 0700 tmpfs) that is removed when curl exits.
 */
QtObject {
  id: root

  // Chat.providers[].kind: which format parse() reads
  property string kind: "anthropic"
  // Stream (a chat reply, parsed per event) or a plain request whose body
  // arrives in `finished` (the models list)
  property bool stream: true

  readonly property bool running: _curl.running
  property bool stopped: false

  // The reply so far (ChatProtocol.newState)
  property var state: ChatProtocol.newState("")

  signal delta(string kind, string text)
  // A reply that ended normally; `body` is the whole response when not
  // streaming
  signal finished(var state, string body)
  signal failed(int status, string message)

  /**
   * @param request { url, headers: ["Name: value"], body (omit for GET) }
   * @param model   the requested model, until the reply names its own
   */
  function start(request, model) {
    if (_curl.running)
      return;
    root.state = ChatProtocol.newState(model ?? "");
    root.stopped = false;
    root._status = 0;
    root._other = [];
    root._bodyPath = "";
    const config = ["url = " + Utils.curlConfigValue(request.url)].concat(request.headers.map(header => "header = " + Utils.curlConfigValue(header)));
    if (request.body !== undefined) {
      root._bodyPath = Paths.runtimeDir + "/axiom-chat-" + Date.now() + "-" + Math.floor(Math.random() * 1e9) + ".json";
      _bodyFile.path = root._bodyPath;
      _bodyFile.setText(request.body);
      config.push("data-binary = " + Utils.curlConfigValue("@" + root._bodyPath));
    }
    root._config = config.join("\n") + "\n";
    const args = ["curl", "-sS", "--connect-timeout", "15", "-K", "-", "-w", "\n" + root._statusMark + "%{http_code}\n"];
    if (root.stream)
      args.splice(1, 0, "-N", "--no-buffer");
    _curl.command = args;
    _curl.stdinEnabled = true;
    _curl.running = true;
  }

  function stop() {
    if (!_curl.running)
      return;
    root.stopped = true;
    _curl.running = false;
  }

  // -- Private --

  readonly property string _statusMark: "\u001eAXIOM_HTTP "
  property string _config: ""
  property string _bodyPath: ""
  property int _status: 0
  // Lines that weren't SSE: an error body, or the whole non-streamed body
  property var _other: []

  function _onLine(line) {
    if (line.startsWith(root._statusMark)) {
      root._status = parseInt(line.substring(root._statusMark.length)) || 0;
      return;
    }
    if (root.stream && line.startsWith("data:")) {
      const deltas = ChatProtocol.parse(root.kind, line.substring(5).trim(), root.state);
      deltas.forEach(d => root.delta(d.kind, d.text));
      return;
    }
    if (root.stream && (line.startsWith("event:") || line.startsWith(":") || line.trim() === ""))
      return;
    root._other.push(line);
  }

  function _onExited(exitCode) {
    if (root._bodyPath !== "") {
      Quickshell.execDetached(["rm", "-f", root._bodyPath]);
      root._bodyPath = "";
    }
    const body = root._other.join("\n");
    if (root.stopped) {
      root.finished(root.state, body);
      return;
    }
    if (exitCode !== 0 && root._status === 0) {
      root.failed(0, _stderr.text.trim().replace(/^curl: \(\d+\)\s*/, "") || `curl exited with ${exitCode}`);
      return;
    }
    if (root._status < 200 || root._status >= 300) {
      root.failed(root._status, ChatProtocol.errorMessage(body) || `HTTP ${root._status}`);
      return;
    }
    if (root.state.error !== "") {
      root.failed(root._status, root.state.error);
      return;
    }
    root.finished(root.state, body);
  }

  property FileView _bodyFile: FileView {
    blockWrites: true
    atomicWrites: false
    printErrors: false
  }

  property Process _curl: Process {
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: data => root._onLine(data)
    }
    stderr: StdioCollector {
      id: _stderr
    }
    onStarted: {
      write(root._config);
      root._config = "";
      stdinEnabled = false; // closes stdin: the end of curl's config
    }
    onExited: exitCode => root._onExited(exitCode)
  }

  Component.onDestruction: root.stop()
}
