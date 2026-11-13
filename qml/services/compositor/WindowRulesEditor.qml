pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.ui

// The Window rules page's editor (WindowRulesManager.editor): a draft of
// the WindowRules section, the selected rule, the edits, and the problems
// Go finds in it (compositor.checkRules on the draft, 300 ms after the last
// edit; the saved rules' are compositor.state's), and how many open windows
// each rule's conditions match (windowRules.match on the draft, while the
// page holds the editor: acquire/release). Unsaved rules are never shown to
// the compositor: no preview.
// Not a singleton: WindowRulesManager owns it.
QtObject {
  id: root

  // --- The draft ---
  readonly property var rules: _draft.local?.rules ?? []
  readonly property bool isDirty: _draft.isDirty
  // The draft's built-in switches (WindowRules.switches)
  readonly property var switches: _draft.local?.switches ?? ({})

  property int selectedIndex: 0
  readonly property var selected: rules[selectedIndex] ?? null
  readonly property string selectedId: selected?.id ?? ""

  // The open windows each draft rule matches ([{ rule, windows }], the
  // draft's order), null until known
  property var _matches: null

  // How many open windows the rule at `index` matches now
  function openCount(index) {
    return WindowRuleIssues.countOf(root._matches, root.rules[index]?.id, index);
  }

  // The page takes the editor: the count runs until it lets go
  function acquire(owner) {
    root._counting.acquire(owner, true);
  }

  function release(owner) {
    root._counting.release(owner);
  }

  // The problems and per-rule facts to show ({ issues, rules },
  // WindowRuleIssues): the draft's while it differs from what's saved (or
  // the saved rules' report isn't known), else the compositor's
  readonly property var report: {
    const saved = WindowRulesManager.savedReport;
    if (root._draftReport !== null && (_draft.isDirty || saved === null))
      return root._draftReport;
    return saved ?? ({
        "issues": [],
        "rules": []
      });
  }

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    _draft.loadIfStale();
  }

  function save() {
    EditsManager.commitTyping();
    return _draft.save();
  }

  function reset() {
    root._load();
  }

  function select(index) {
    EditsManager.commitTyping();
    root.selectedIndex = Math.max(0, Math.min(index, root.rules.length - 1));
  }

  // Whether a rule differs from its saved version (matched by id)
  function changed(index) {
    const item = root.rules[index];
    const saved = (_draft.saved?.rules ?? []).find(r => r.id === item?.id);
    return !saved || !Utils.deepEqual(saved, item);
  }

  // A new rule, last (lowest priority), selected
  function add() {
    EditsManager.commitTyping();
    const local = root._local();
    const name = I18n.tr("New rule");
    const rule = ({
        "id": Utils.newId(Utils.slug(name) || "rule", local.rules),
        "name": name,
        "windows": [
          {
            "conditions": [root._newCondition()]
          }
        ]
      });
    local.rules.push(ConfigManager.withDefaults(rule, "WindowRule"));
    root._apply();
    root.select(local.rules.length - 1);
  }

  // A new rule, last and selected, from what a window gave
  // (WindowRulesManager.fromWindow's result): named after its installed
  // app, else its title, else its app id
  function addRuleFrom(result) {
    EditsManager.commitTyping();
    const local = root._local();
    if (!local || !result?.kind)
      return;
    const window = result.window ?? ({});
    const name = (window.appId ? DesktopEntries.heuristicLookup(window.appId)?.name : "") || window.title || window.appId || I18n.tr("New rule");
    const rule = ({
        "id": Utils.newId(Utils.slug(name) || "rule", local.rules),
        "name": name,
        "windows": [result.kind]
      });
    local.rules.push(ConfigManager.withDefaults(rule, "WindowRule"));
    root._apply();
    root.select(local.rules.length - 1);
  }

  // Adds a kind to the rule `ruleId` (found by id: the selection may have
  // moved since a picker opened); a kind still the new-rule placeholder
  // (one empty app id condition) is replaced
  function addKindFrom(ruleId, kind) {
    const rule = root._local()?.rules.find(r => r.id === ruleId);
    if (!rule || !kind)
      return;
    EditsManager.commitTyping();
    const last = rule.windows[rule.windows.length - 1];
    const placeholder = last && last.conditions.length === 1 && last.conditions[0].field === "appId" && last.conditions[0].op === "is" && last.conditions[0].value === "";
    if (placeholder)
      rule.windows.splice(rule.windows.length - 1, 1);
    rule.windows.push(kind);
    root._apply();
  }

  // Add from open window: a kind from the window `windowId` for the rule
  // selected now
  function addKindFromWindow(windowId) {
    const ruleId = root.selectedId;
    WindowRulesManager.fromWindow(windowId, result => {
      if (result)
        root.addKindFrom(ruleId, result.kind);
    });
  }

  // Add app: a kind for an installed app, for the rule selected now
  function addApp(desktopId) {
    root.addKindFrom(root.selectedId, {
      "conditions": [
        {
          "field": "app",
          "op": "is",
          "value": desktopId
        }
      ]
    });
  }

  function duplicate(index) {
    EditsManager.commitTyping();
    const local = root._local();
    const source = local.rules[index];
    if (!source)
      return;
    const copy = Utils.clone(source);
    copy.id = Utils.newId(source.id, local.rules);
    copy.name = I18n.tr("{0} (copy)", source.name);
    local.rules.splice(index + 1, 0, copy);
    root._apply();
    root.select(index + 1);
  }

  function remove(index) {
    EditsManager.commitTyping();
    const local = root._local();
    if (!local.rules[index])
      return;
    const selectedId = root.selectedId;
    local.rules.splice(index, 1);
    root._apply();
    const kept = local.rules.findIndex(rule => rule.id === selectedId);
    root.selectedIndex = Math.max(0, kept >= 0 ? kept : Math.min(index, local.rules.length - 1));
  }

  // Moves the rule at `from` to before row `to` (the count: after the
  // last), counted as if it were still in place: dropped where it was,
  // nothing moves. The selection follows the moved rule
  function move(from, to) {
    if (to === from || to === from + 1)
      return;
    EditsManager.commitTyping();
    const rules = root._local().rules;
    const selectedId = root.selectedId;
    const [moved] = rules.splice(from, 1);
    rules.splice(to > from ? to - 1 : to, 0, moved);
    root._apply();
    root.selectedIndex = Math.max(0, rules.findIndex(rule => rule.id === selectedId));
  }

  function setEnabled(index, on) {
    const rule = root._local().rules[index];
    if (!rule || rule.enabled === on)
      return;
    rule.enabled = on;
    root._apply();
  }

  // Sets a key of the selected rule: `path` a key or a list of keys into it
  // (["window", "size", "width"])
  function set(path, value) {
    const rule = root._local().rules[root.selectedIndex];
    if (!rule)
      return;
    const keys = Array.isArray(path) ? path : [path];
    let target = rule;
    for (const key of keys.slice(0, -1)) {
      if (target[key] === null || typeof target[key] !== "object")
        target[key] = {};
      target = target[key];
    }
    const last = keys[keys.length - 1];
    if (Utils.deepEqual(target[last], value))
      return;
    if (value === undefined)
      delete target[last];
    else
      target[last] = value;
    root._apply();
  }

  // Sets a key of the built-in switches: `path` a list of keys under them
  // (["gamesSpecial", "enabled"])
  function setSwitch(path, value) {
    const local = root._local();
    if (!local?.switches)
      return;
    let target = local.switches;
    for (const key of path.slice(0, -1)) {
      if (target[key] === null || typeof target[key] !== "object")
        target[key] = {};
      target = target[key];
    }
    const last = path[path.length - 1];
    if (Utils.deepEqual(target[last], value))
      return;
    target[last] = value;
    root._apply();
  }

  // Copy as rule: the built-in switch `key` ("steamFloat", "gamesSpecial")
  // as a rule of the user's: last among the user's rules (just above the
  // built-ins, where the switch ranked), selected and unsaved, with the switch
  // turned off so it isn't done twice
  function copySwitch(key) {
    EditsManager.commitTyping();
    const draft = root._local();
    if (!draft)
      return;
    WindowRulesManager.builtin(key, draft, builtinRule => {
      const local = root._local();
      if (!builtinRule || !local)
        return;
      // The switch's own title, a schema string
      const props = ConfigManager.configSchema.properties.WindowRules.properties.switches.properties;
      const name = I18n.tr(key === "steamFloat" ? props.steamFloat.title : props.gamesSpecial.properties.enabled.title);
      const rule = Object.assign({
        "id": Utils.newId(Utils.slug(name) || "rule", local.rules),
        "name": name
      }, builtinRule);
      local.rules.push(ConfigManager.withDefaults(rule, "WindowRule"));
      root._apply();
      root.setSwitch(key === "steamFloat" ? [key] : [key, "enabled"], false);
      root.select(local.rules.length - 1);
    });
  }

  function addKind() {
    root._selectedRule()?.windows.push({
      "conditions": [root._newCondition()]
    });
    root._apply();
  }

  function removeKind(k) {
    EditsManager.commitTyping();
    root._selectedRule()?.windows.splice(k, 1);
    root._apply();
  }

  function addCondition(k) {
    root._selectedRule()?.windows[k]?.conditions.push(root._newCondition());
    root._apply();
  }

  function removeCondition(k, c) {
    EditsManager.commitTyping();
    root._selectedRule()?.windows[k]?.conditions.splice(c, 1);
    root._apply();
  }

  // Sets a key of a condition; a new field resets a test it doesn't allow
  // to "is"
  function setCondition(k, c, key, value) {
    const condition = root._selectedRule()?.windows[k]?.conditions[c];
    if (!condition || condition[key] === value)
      return;
    const previous = condition[key];
    condition[key] = value;
    if (key === "field") {
      // A typed text is no desktop file, and the reverse
      if ((value === "app") !== (previous === "app"))
        condition.value = "";
      const allowed = root._opSchema["x-enumShowIf"]?.[condition.op];
      if (allowed && !SchemaLayout.showIfHolds(allowed, name => condition[name]))
        condition.op = "is";
    }
    root._apply();
  }

  // An issue as the user reads it: its English message translated, its
  // arguments filled in (a field's id as its label)
  // Every message of windowrules/validate.go, so each is translated (a Go
  // test keeps the list complete):
  // I18n.tr("This rule has no id.")
  // I18n.tr("Another rule above has the same id.")
  // I18n.tr("Add at least one kind of window.")
  // I18n.tr("This kind has no conditions, so it would match every window.")
  // I18n.tr("{0} can't be tested this way.")
  // I18n.tr("A kind can test {0} only once with is, contains or matches: join them into one pattern.")
  // I18n.tr("A Steam game id is a number.")
  // I18n.tr("Enter a value.")
  // I18n.tr("Patterns can't use {0} here.")
  // I18n.tr("This pattern doesn't work: {0}")
  // I18n.tr("Give both a width and a height.")
  // I18n.tr("Pick a workspace or a special workspace, not both.")
  // I18n.tr("A workspace is a number from 1 up, or a name.")
  // I18n.tr("A special workspace id is up to 32 letters, digits, dots, dashes or underscores.")
  // I18n.tr("Pick when it applies.")
  // I18n.tr("Pick performance or power saver.")
  // I18n.tr("Pick at least one place to hide it from.")
  // I18n.tr("Pick at least one shortcut to pause.")
  // I18n.tr("Keep at least one shortcut, your way out.")
  // I18n.tr("The shortcuts you keep are paused or have no key: keep one that works, your way out.")
  // I18n.tr("All except works only while the window is focused or fullscreen.")
  // I18n.tr("Shortcut {0} no longer exists.")
  // I18n.tr("Pick a special workspace.")
  function issueText(issue) {
    const labels = root._fieldSchema["x-enumLabels"] ?? ({});
    const args = (issue.args ?? []).map(arg => labels[arg] !== undefined ? I18n.tr(labels[arg]) : arg);
    return I18n.tr(issue.message, ...args);
  }

  // -- Private --
  readonly property var _conditionSchema: ConfigManager.configSchema.definitions.WindowRuleCondition.properties
  readonly property var _fieldSchema: root._conditionSchema.field
  readonly property var _opSchema: root._conditionSchema.op

  property ConfigDraft _draft: ConfigDraft {
    path: ["WindowRules"]
    onLoaded: {
      root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.rules.length - 1));
      root._draftReport = null;
      ++root._sequence;
      root._checkSoon();
    }
  }

  // The newest draft report, and the number of the check that asked for it
  property var _draftReport: null
  property int _sequence: 0

  // Pages holding the editor: the count runs while there is one
  property ConsumerRegistry _counting: ConsumerRegistry {}
  property int _matchSequence: 0

  property Timer _timer: Timer {
    interval: 300
    onTriggered: root._check()
  }

  // The compositor's abilities change what is a problem
  property Connections _supports: Connections {
    target: CompositorManager

    function onSupportsChanged() {
      root._checkSoon();
    }
  }

  // A window opening or closing, or the page being taken, recounts
  property Connections _windows: Connections {
    target: WindowRulesManager

    function onStateChanged() {
      root._count();
    }
  }

  property Connections _counted: Connections {
    target: root._counting

    function onActiveChanged() {
      root._count();
    }
  }

  function _checkSoon() {
    root._timer.restart();
  }

  // A report changing never edits the draft
  function _check() {
    if (_draft.local === null)
      return;
    const sequence = ++root._sequence;
    CompositorConfigManager.checkRules(_draft.local, report => {
      if (report !== null && sequence === root._sequence)
        root._draftReport = report;
    });
    root._count();
  }

  // The count of open windows per draft rule; only sets `_matches`, never
  // the draft. The latest answer wins
  function _count() {
    if (!root._counting.active || _draft.local === null)
      return;
    const sequence = ++root._matchSequence;
    WindowRulesManager.match(_draft.local, rows => {
      if (rows !== null && sequence === root._matchSequence)
        root._matches = rows;
    });
  }

  function _local() {
    return _draft.local;
  }

  function _selectedRule() {
    return root._local().rules[root.selectedIndex] ?? null;
  }

  function _newCondition() {
    return {
      "field": "appId",
      "op": "is",
      "value": ""
    };
  }

  function _load() {
    EditsManager.commitTyping();
    _draft.load();
  }

  // After an edit in place
  function _apply() {
    _draft.changed();
    root._checkSoon();
  }
}
