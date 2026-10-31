pragma Singleton
import QtQuick
import Quickshell
import qs.services.core

/*
 * Math, units and currencies through qalc (libqalculate, which fetches and
 * caches its own exchange rates), for the launcher's calculator rows and
 * the Calculator module. Each caller evaluates under its own key, so they
 * don't take each other's answers:
 *   evaluate(key, expr)   asks for expr (debounced; "" forgets the key's)
 *   resultFor(key, expr)  qalc's answer once it's in, else ""
 *   busyFor(key)          an answer is on its way
 * `evaluated(key)` fires when one lands. One qalc runs at a time; a key
 * asked again while its last is running is run again for the newest only.
 * `history` is the last answers a caller kept ({ expr, result }, newest
 * first), and `draft` the Calculator module's unfinished expression (so
 * it's still there when the overlay opens again); both are kept across QML
 * reloads but not restarts.
 */
Singleton {
  id: root

  // Whether qalc is installed: undefined until checked (by the first
  // evaluate, or a caller's DependencyManager.check)
  readonly property var qalc: DependencyManager.found.qalc

  readonly property var history: JSON.parse(_kept.history)
  readonly property string draft: _kept.draft
  readonly property int _maxHistory: 20

  signal evaluated(string key)

  function evaluate(key, expr) {
    const wanted = String(expr ?? "").trim();
    const slot = root._slots[key];
    if (slot && slot.expr === wanted)
      return;
    root._slots[key] = {
      expr: wanted,
      doneExpr: slot?.doneExpr ?? "",
      result: slot?.result ?? ""
    };
    root._slotsChanged();
    if (wanted === "")
      return;
    DependencyManager.check(["qalc"]);
    if (!root._queue.includes(key))
      root._queue.push(key);
    _debounce.restart();
  }

  // qalc's answer to `expr` under `key`, or "" (not in yet, or no answer)
  function resultFor(key, expr) {
    const slot = root._slots[key];
    return slot && slot.doneExpr === String(expr ?? "").trim() ? slot.result : "";
  }

  // Whether `expr` has been answered under `key` (with or without a result)
  function answered(key, expr) {
    return root._slots[key]?.doneExpr === String(expr ?? "").trim();
  }

  function busyFor(key) {
    const slot = root._slots[key];
    return !!slot && slot.expr !== "" && slot.expr !== slot.doneExpr;
  }

  function forget(key) {
    delete root._slots[key];
    root._queue = root._queue.filter(k => k !== key);
    root._slotsChanged();
  }

  // Puts an answer at the top of the history (once; an older copy goes).
  // A value that is its own answer (one = carried on with) isn't kept
  function keep(expr, result) {
    if (!expr || !result || expr === result)
      return;
    const kept = root.history.filter(h => h.expr !== expr);
    kept.unshift({
      expr: expr,
      result: result
    });
    _kept.history = JSON.stringify(kept.slice(0, root._maxHistory));
  }

  function setDraft(text) {
    _kept.draft = text;
  }

  function clearHistory() {
    _kept.history = "[]";
  }

  // --- Private ---

  // { key: { expr, doneExpr, result } }
  property var _slots: ({})
  // Keys waiting for qalc, oldest first
  property var _queue: []

  PersistentProperties {
    id: _kept
    reloadableId: "axiomCalculator"
    property string history: "[]"
    property string draft: ""
  }

  Timer {
    id: _debounce
    interval: 120
    onTriggered: root._next()
  }

  property bool _running: false

  function _next() {
    if (root._running || root._queue.length === 0)
      return;
    const key = root._queue.shift();
    const slot = root._slots[key];
    if (!slot || slot.expr === "" || slot.expr === slot.doneExpr)
      return root._next();
    const expr = slot.expr;
    root._running = true;
    CommandManager.run(["qalc", "-t", "--", expr], (exitCode, stdout) => {
      root._running = false;
      const slot = root._slots[key];
      if (slot) {
        // qalc echoes what it can't evaluate
        const answer = stdout.trim().split("\n").pop().trim();
        const plain = s => s.replace(/\s/g, "").replace(/−/g, "-");
        slot.result = answer !== "" && plain(answer) !== plain(expr) ? answer : "";
        slot.doneExpr = expr;
        if (slot.expr !== expr && !root._queue.includes(key))
          root._queue.push(key);
        root._slotsChanged();
        root.evaluated(key);
      }
      Qt.callLater(root._next);
    }, null, true);
  }
}
