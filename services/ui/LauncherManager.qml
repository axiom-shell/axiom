pragma Singleton

import QtQuick
import Quickshell

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.apps

/*
 * LauncherManager turns the launcher's search text into result rows and
 * runs them. The first character picks what's searched:
 *   /  shell commands (LauncherCommands)   =  calculator (qalc)
 *   >  run a shell command                 ?  web search
 *   @  ask the chat                        :  clipboard history
 *   ;  emoji (EmojiManager)
 * and anything else searches apps and open windows, with a calculator row
 * when the text is math and a web search row last. Every row is
 *   { kind, image, glyph, title, usage, subtitle, hint, complete, run(shift) }
 * where image is an icon path or url, glyph a Material Symbols name, complete the
 * text Tab puts in the search field, and run() returns true to close the
 * launcher, false to keep it open, or a string to search for instead.
 * App launches and commands run are counted (with their last time) for
 * frecency sorting.
 */
QtObject {
  id: root

  // --- Public Properties ---
  property var results: []
  // What the search text is: "apps" | "commands" | "calc" | "run" | "web" |
  // "chat" | "clipboard" | "emoji"
  property string mode: "apps"
  // The results are the frequent apps shown before anything is typed
  property bool frequent: false
  // The text results was built from
  property string text: ""
  // { id: { count, last } }
  property var usage: ({})
  // { command name: { count, last } }
  property var commandUsage: ({})
  // { id: last launch time }, for Favourites
  readonly property var launchTimes: Object.keys(usage).reduce((times, id) => {
    times[id] = usage[id].last;
    return times;
  }, {})

  // --- Public Methods ---

  function query(text) {
    root.text = text;
    const raw = text.replace(/^\s+/, "");
    const prefix = raw.charAt(0);
    const rest = raw.slice(1);
    root.frequent = false;

    if (prefix === "/" && LauncherConfig.commands)
      return _set("commands", _commandRows(rest));
    if (prefix === "=" && LauncherConfig.calculator)
      return _set("calc", _calcRows(rest.trim()));
    if (prefix === ">" && LauncherConfig.runCommands)
      return _set("run", [_runRow(rest.trim())]);
    if (prefix === "?" && LauncherConfig.webSearch)
      return _set("web", [_webRow(rest.trim())]);
    if (prefix === "@" && LauncherConfig.chat)
      return _set("chat", [_chatRow(rest.trim())]);
    if (prefix === ":" && LauncherConfig.clipboard)
      return _set("clipboard", _clipboardRows(rest.trim()));
    if (prefix === ";" && LauncherConfig.emoji)
      return _set("emoji", _emojiRows(rest.trim()));

    const q = raw.trim();
    if (q === "") {
      _requestCalc("");
      root.frequent = LauncherConfig.showRecent;
      return _set("apps", root.frequent ? _frequentRows() : []);
    }
    const math = LauncherConfig.calculator && Search.looksLikeMath(q);
    _requestCalc(math ? q : "");
    let rows = [];
    if (math && _calcReady(q))
      rows.push(_calcRow(q));
    rows = rows.concat(_searchRows(q));
    if (LauncherConfig.webSearch)
      rows.push(_webRow(q));
    _set("apps", rows);
  }

  // Runs results[index]; see the row's run()
  function activate(index, shift) {
    const row = results[index];
    return row ? row.run(!!shift) : false;
  }

  // The text Tab puts in the search field for results[index], or ""
  function completion(index) {
    return results[index]?.complete ?? "";
  }

  function clear() {
    root._armed = "";
    query("");
  }

  function launchApp(appEntry) {
    if (!appEntry)
      return false;
    try {
      usage = Utils.recordUse(usage, appEntry.id, Date.now());
      _stateHandler.save(usage);

      // DesktopEntry.execute() ignores Terminal=true
      if (appEntry.runInTerminal)
        Quickshell.execDetached(Apps.inTerminal(appEntry.command));
      else
        appEntry.execute();
      return true;
    } catch (e) {
      console.warn("[LauncherManager] Failed to launch app:", e);
      return false;
    }
  }

  // --- Apps & windows ---

  readonly property int _searchLimit: 50

  // The apps best matching `text` (by name, generic name and keywords,
  // then frecency), as desktop entries; the most used ones when it's empty
  function searchApps(text, limit) {
    const q = String(text ?? "").trim().toLowerCase();
    const apps = _apps();
    if (!q)
      return apps.slice().sort((a, b) => _frecency(b.id) - _frecency(a.id) || a.name.localeCompare(b.name)).slice(0, limit);
    const scored = [];
    for (const app of apps) {
      const s = _appScore(app, q);
      if (s > 0)
        scored.push({
          s: s,
          app: app
        });
    }
    scored.sort((a, b) => b.s - a.s || a.app.name.localeCompare(b.app.name));
    return scored.slice(0, limit).map(m => m.app);
  }

  // How well an app matches the lowercased query (name, generic name, then
  // keywords), plus a frecency bonus; 0 when it doesn't
  function _appScore(app, q) {
    const keyword = Math.max(0, ...app.keywords.map(k => Search.score(k, q)).filter(s => s >= 50));
    const s = Math.max(Search.score(app.name, q), 0.75 * Search.score(app.genericName, q), 0.6 * keyword);
    return s > 0 ? s + Math.min(25, 8 * Math.log2(1 + _frecency(app.id))) : 0;
  }

  function _apps() {
    const hidden = LauncherConfig.hiddenApps.map(id => id.replace(/\.desktop$/, ""));
    return DesktopEntries.applications.values.filter(app => !app.noDisplay && !hidden.includes(app.id));
  }

  // How often and how lately an app was launched
  function _frecency(id) {
    return _entryFrecency(usage[id]);
  }

  function _entryFrecency(entry) {
    return Search.frecency(entry, Date.now());
  }

  function _appRow(app) {
    return {
      kind: "app",
      image: Quickshell.iconPath(app.icon, "application-x-executable"),
      title: app.name,
      subtitle: app.genericName || app.comment || "",
      hint: app.runInTerminal ? I18n.tr("Terminal") : "",
      run: () => root.launchApp(app)
    };
  }

  function _windowRow(win) {
    return {
      kind: "window",
      image: IconResolver.resolveWindowIcon(win.appId, win.title),
      title: win.title || win.appId,
      subtitle: I18n.tr("{0} · workspace {1}", win.appId, win.workspaceName),
      hint: I18n.tr("Window"),
      run: () => {
        CompositorManager.focusWindow(win.id);
        return true;
      }
    };
  }

  function _searchRows(q) {
    q = q.toLowerCase();
    const scored = [];
    for (const app of _apps()) {
      const s = _appScore(app, q);
      if (s > 0)
        scored.push({
          s: s,
          name: app.name,
          row: () => _appRow(app)
        });
    }
    if (LauncherConfig.windows) {
      for (const win of CompositorManager.windows) {
        if (win.hidden)
          continue;
        // No fuzzy matches: titles are long enough to match most anything
        const s = Math.max(0.9 * Search.score(win.title, q), 0.8 * Search.score(win.appId, q));
        if (s >= 40)
          scored.push({
            s: s - 5,
            name: win.title,
            row: () => _windowRow(win)
          });
      }
    }
    scored.sort((a, b) => b.s - a.s || a.name.localeCompare(b.name));
    return scored.slice(0, _searchLimit).map(m => m.row());
  }

  function _frequentRows() {
    return _apps().filter(app => usage[app.id]).sort((a, b) => _frecency(b.id) - _frecency(a.id) || a.name.localeCompare(b.name)).slice(0, LauncherConfig.maxResults).map(app => _appRow(app));
  }

  // --- Commands ---

  property LauncherCommands _commands: LauncherCommands {}
  // A command waiting for its confirming second Enter
  property string _armed: ""

  property Timer _disarm: Timer {
    interval: 3000
    onTriggered: {
      root._armed = "";
      root._refresh();
    }
  }

  // Re-reads the rows after a command that keeps the launcher open, once
  // its (often asynchronous) state change has landed
  property Timer _refreshLater: Timer {
    interval: 250
    onTriggered: root._refresh()
  }

  // /config save and restore list the saved configs, which the folder
  // model reads in the background (at first only once something has
  // reached SavedConfigsManager, as this does)
  property Connections _savedConfigUpdates: Connections {
    target: SavedConfigsManager.model
    function onCountChanged() {
      if (root.mode === "commands")
        root._refresh();
    }
  }

  function _refresh() {
    query(root.text);
  }

  function _infoRow(title, subtitle) {
    return {
      kind: "info",
      glyph: "info",
      title: title,
      subtitle: subtitle ?? "",
      run: () => false
    };
  }

  function _commandRows(body) {
    const commands = _commands.list.filter(c => !c.available || c.available());
    const space = body.indexOf(" ");
    if (space < 0) {
      const q = body.toLowerCase();
      const matches = commands.map((c, i) => ({
            c: c,
            i: i,
            f: _entryFrecency(commandUsage[c.name]),
            s: q === "" ? 1 : Math.max(Search.score(c.name, q), ...c.aliases.map(a => 0.9 * Search.score(a, q)))
          })).filter(m => m.s > 0).map(m => Object.assign(m, {
          s: m.s + Math.min(25, 8 * Math.log2(1 + m.f))
        }));
      matches.sort((a, b) => b.s - a.s || b.f - a.f || a.i - b.i);
      return matches.length > 0 ? matches.map(m => _commandRow(m.c, "")) : [_infoRow(I18n.tr("No command \"{0}\"", body), I18n.tr("Type / to list every command"))];
    }

    const name = body.slice(0, space).toLowerCase();
    const arg = body.slice(space + 1);
    const command = commands.find(c => c.name === name || c.aliases.includes(name));
    if (!command)
      return [_infoRow(I18n.tr("No command \"{0}\"", name), I18n.tr("Type / to list every command"))];
    if (!command.options)
      return [_commandRow(command, arg)];

    const q = arg.trim().toLowerCase();
    const options = command.options(arg).map((o, i) => ({
          o: o,
          i: i,
          s: q === "" || o.matched ? 1 : Search.score(o.title, q)
        })).filter(m => m.s > 0);
    options.sort((a, b) => b.s - a.s || a.i - b.i);
    let rows = [];
    if (!command.needsArg && q === "")
      rows.push(_commandRow(command, ""));
    rows = rows.concat(options.map(m => _optionRow(command, m.o)));
    if (options.length === 0 && q !== "")
      rows.push(command.needsArg ? _infoRow(I18n.tr("No matches"), command.description()) : _commandRow(command, arg));
    return rows;
  }

  function _commandRow(command, arg) {
    const takesArg = !!(command.options || command.usage);
    const armed = root._armed === command.name;
    return {
      kind: "command",
      glyph: command.glyph,
      title: "/" + command.name + (arg.trim() ? " " + arg.trim() : ""),
      usage: arg.trim() ? "" : command.usage ?? "",
      subtitle: command.description(),
      hint: armed ? I18n.tr("Press Enter again to confirm") : command.status?.() ?? "",
      armed: armed,
      complete: "/" + command.name + (takesArg ? " " : ""),
      run: () => command.needsArg && arg.trim() === "" ? "/" + command.name + " " : root._runCommand(command, arg, undefined)
    };
  }

  function _optionRow(command, option) {
    const next = option.value?.next;
    return {
      kind: "option",
      glyph: option.image ? "" : option.glyph || command.glyph,
      image: option.image ?? "",
      title: option.title,
      subtitle: option.subtitle ?? "",
      complete: next !== undefined ? "/" + command.name + " " + next : "/" + command.name + " " + option.title,
      run: () => root._runCommand(command, option.title, option.value)
    };
  }

  function _runCommand(command, arg, value) {
    if (command.confirm && root._armed !== command.name) {
      root._armed = command.name;
      _disarm.restart();
      _refresh();
      return false;
    }
    root._armed = "";
    _recordCommand(command.name);
    const result = command.run(arg, value);
    if (typeof result === "string")
      return result;
    if (result === false) {
      _refresh();
      _refreshLater.restart();
      return false;
    }
    return true;
  }

  // --- Calculator ---

  readonly property bool _qalc: CalculatorManager.qalc === true
  // The expression the search wants answered
  property string _calcExpr: ""

  function _calcReady(expr) {
    return CalculatorManager.resultFor("launcher", expr) !== "";
  }

  function _requestCalc(expr) {
    root._calcExpr = expr;
    if (root._qalc || expr === "")
      CalculatorManager.evaluate("launcher", expr);
  }

  function _calcRow(expr) {
    const result = CalculatorManager.resultFor("launcher", expr);
    return {
      kind: "calc",
      glyph: "calculate",
      title: result,
      subtitle: expr,
      hint: I18n.tr("Enter to copy"),
      complete: "=" + result,
      run: () => {
        ClipboardManager.copyText(result);
        CalculatorManager.keep(expr, result);
        return true;
      }
    };
  }

  function _calcRows(expr) {
    if (!root._qalc)
      return [_infoRow(I18n.tr("The calculator needs qalc"), I18n.tr("Install libqalculate"))];
    _requestCalc(expr);
    if (expr === "")
      return [_infoRow(I18n.tr("Type an expression"), I18n.tr("Math, units and currencies, e.g. 5 km to mi"))];
    if (_calcReady(expr))
      return [_calcRow(expr)];
    return [_infoRow(expr, CalculatorManager.busyFor("launcher") ? I18n.tr("Calculating…") : I18n.tr("No result"))];
  }

  property Connections _calcUpdates: Connections {
    target: CalculatorManager
    function onEvaluated(key) {
      if (key === "launcher" && root._calcExpr !== "")
        root._refresh();
    }
  }

  // --- Run & web ---

  function _runRow(command) {
    return {
      kind: "run",
      glyph: "terminal",
      title: command || I18n.tr("Type a command"),
      subtitle: I18n.tr("Enter runs it, Shift+Enter runs it in {0}", Apps.terminal.trim() || "xdg-terminal-exec"),
      run: shift => {
        if (command === "")
          return false;
        if (shift)
          Quickshell.execDetached(Apps.inTerminal(["sh", "-c", command + "; exec \"${SHELL:-sh}\""]));
        else
          Quickshell.execDetached(["sh", "-c", command]);
        return true;
      }
    };
  }

  // Asks the overlay's chat, in a new conversation with the default preset
  function _chatRow(q) {
    const preset = ChatConfig.preset(ChatConfig.defaultPreset);
    return {
      kind: "chat",
      glyph: preset.icon || "smart_toy",
      title: q ? I18n.tr("Ask {0}: \"{1}\"", preset.name, q) : I18n.tr("Type a question for the chat"),
      subtitle: ChatConfig.provider(preset.provider)?.name ?? "",
      run: () => {
        if (q === "")
          return false;
        // After the launcher has closed, so the overlay gets the keyboard
        Qt.callLater(() => ChatManager.ask(q));
        return true;
      }
    };
  }

  function _webRow(q) {
    const engine = LauncherConfig.searchEngine;
    const host = (engine.match(/^\w+:\/\/([^/]+)/)?.[1] ?? engine).replace(/^www\./, "");
    return {
      kind: "web",
      glyph: "web",
      title: q ? I18n.tr("Search the web for \"{0}\"", q) : I18n.tr("Type something to search for"),
      subtitle: host,
      run: () => {
        if (q === "")
          return false;
        Qt.openUrlExternally(engine.includes("{}") ? engine.replace("{}", encodeURIComponent(q)) : engine + encodeURIComponent(q));
        return true;
      }
    };
  }

  // --- Clipboard ---

  function _clipboardRows(query) {
    if (!ClipboardManager.available)
      return [_infoRow(I18n.tr("No clipboard history here"), I18n.tr("This compositor offers no clipboard control"))];
    // Pins first, then the history without them
    const entries = ClipboardManager.pins.concat(ClipboardManager.entries.filter(e => !ClipboardManager.isPinned(e)));
    if (entries.length === 0)
      return [_infoRow(I18n.tr("The clipboard history is empty"), I18n.tr("Copy something and it shows up here"))];
    const q = query.toLowerCase();
    let matches = entries.map((e, i) => ({
          e: e,
          i: i,
          s: q === "" ? 1 : Math.max(Search.score(e.format ? I18n.tr("Image {0}", e.dimensions) : e.text.trim().split("\n")[0], q), e.text.toLowerCase().includes(q) ? 40 : 0)
        })).filter(m => m.s > 0);
    matches.sort((a, b) => b.s - a.s || a.i - b.i);
    const rows = matches.slice(0, _searchLimit).map(m => _clipboardRow(m.e));
    if (q === "")
      rows.push({
        kind: "command",
        glyph: "delete_sweep",
        title: I18n.tr("Clear the clipboard history"),
        subtitle: I18n.tr("{0} entries", entries.length),
        run: () => {
          ClipboardManager.clear();
          return false;
        }
      });
    return rows.length > 0 ? rows : [_infoRow(I18n.tr("No matches"), I18n.tr("{0} entries", entries.length))];
  }

  function _clipboardRow(entry) {
    if (entry.format || entry.html)
      return _clipboardImageRow(entry);
    const lines = entry.text.trim().split("\n");
    const first = lines[0].trim();
    const details = [];
    if (lines.length > 1)
      details.push(I18n.tr("{0} lines", lines.length));
    if (entry.time > 0)
      details.push(I18n.formatDate(new Date(entry.time), I18n.dateFormat("time24")));
    return {
      kind: "clipboard",
      glyph: entry.pinned ? "keep" : /^\[\[ binary data/.test(first) ? "image" : "content_paste",
      title: first.length > 120 ? first.slice(0, 120) + "…" : first,
      subtitle: details.join(" · "),
      hint: entry.pinned ? I18n.tr("Shift+Enter unpins") : I18n.tr("Shift+Enter removes"),
      run: shift => {
        if (shift) {
          if (entry.pinned)
            ClipboardManager.unpin(entry);
          else
            ClipboardManager.remove(entry);
          return false;
        }
        ClipboardManager.copy(entry);
        return true;
      }
    };
  }

  // An image, with its thumbnail, or HTML that is just
  // an image, previewed from its url
  function _clipboardImageRow(entry) {
    return {
      kind: "clipboard",
      glyph: "image",
      image: entry.image,
      title: entry.html ? (entry.image ? I18n.tr("Image from {0}", entry.image.match(/^\w+:\/\/([^/]+)/)[1]) : I18n.tr("Image")) : I18n.tr("Image {0}", entry.dimensions),
      subtitle: entry.html ? I18n.tr("HTML") + (entry.image ? " · " + entry.image : "") : entry.format.toUpperCase() + " · " + entry.size,
      hint: I18n.tr("Shift+Enter removes"),
      run: shift => {
        if (shift)
          ClipboardManager.remove(entry);
        else
          ClipboardManager.copy(entry);
        return !shift;
      }
    };
  }

  property Connections _clipboardUpdates: Connections {
    target: ClipboardManager
    function onEntriesChanged() {
      if (root.mode === "clipboard")
        root._refresh();
    }
    function onPinsChanged() {
      if (root.mode === "clipboard")
        root._refresh();
    }
    function onAvailableChanged() {
      if (root.mode === "clipboard")
        root._refresh();
    }
  }

  // --- Emoji ---

  // EmojiManager.search: most used first with no text, else by name
  function _emojiRows(query) {
    if (EmojiManager.entries().length === 0)
      return [_infoRow(I18n.tr("No emoji list"), I18n.tr("Run scripts/generate_emoji.py"))];
    const matches = EmojiManager.search(query, _searchLimit);
    return matches.length > 0 ? matches.map(e => _emojiRow(e)) : [_infoRow(I18n.tr("No matches"), I18n.tr("Search emoji by name or keyword"))];
  }

  function _emojiRow(entry) {
    const canType = EmojiManager.canType;
    return {
      kind: "emoji",
      glyph: entry.e,
      title: entry.n.charAt(0).toUpperCase() + entry.n.slice(1),
      subtitle: entry.k.length > 0 ? entry.k.slice(0, 6).join(", ") : entry.g,
      hint: canType ? I18n.tr("Shift+Enter types it") : "",
      complete: ";" + entry.n,
      run: shift => {
        EmojiManager.copy(entry.e);
        if (shift && canType)
          EmojiManager.type(entry.e);
        return true;
      }
    };
  }

  // The Shift+Enter hint, once wtype has been looked for
  property Connections _emojiUpdates: Connections {
    target: EmojiManager
    function onCanTypeChanged() {
      if (root.mode === "emoji")
        root._refresh();
    }
  }

  // --- Private ---

  property var _stateHandler: StateManager.createStateHandler("launcher")

  property var _commandStateHandler: StateManager.createStateHandler("launcher-commands")

  function _recordCommand(name) {
    commandUsage = Utils.recordUse(commandUsage, name, Date.now());
    _commandStateHandler.save(commandUsage);
  }

  function _set(mode, rows) {
    root.mode = mode;
    root.results = rows;
  }

  Component.onCompleted: {
    usage = _stateHandler.load({});
    commandUsage = _commandStateHandler.load({});
    DependencyManager.check(["qalc"]);
  }
}
