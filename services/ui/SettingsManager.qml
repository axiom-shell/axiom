pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.services.apps

/* The settings page's working copy of the config. Edits show live as
 * they're made, each setting a preview (ConfigManager.setPreview) and never
 * part of the running config, so another save doesn't carry them;
 * saveChanges() persists them, resetChanges() drops them. Only the
 * settings actually edited are saved, onto the latest config, so changes
 * made elsewhere meanwhile (a theme, a wallpaper, the bar editor) survive.
 *
 * Also keeps the page's own state (category, search), since the page is
 * unloaded whenever the overlay closes. */
QtObject {
  id: root

  property ConfigDraft _draft: ConfigDraft {
    id: draft
    onLoaded: root._clearPreviews()
  }
  readonly property alias localConfig: draft.local
  readonly property alias savedConfig: draft.saved
  readonly property alias isDirty: draft.isDirty

  // Key paths ("Appearance.font.size") that differ from the saved config;
  // arrays count as one value
  readonly property var changedPaths: _diff(draft.local, draft.saved, [])
  readonly property int changedCount: changedPaths.length

  // Installed cursor themes (XCursor or hyprcursor), for the
  // "cursorThemes" options; listed once, when this is first used
  readonly property var cursorThemes: _cursorThemes
  property var _cursorThemes: []

  // The settings page's selected category and search text
  property string category: ""
  property string query: ""
  // The page lists only the settings that differ from their defaults
  // (`changedSet`), from every category, as search results
  property bool changedOnly: false
  // The settings that differed from their defaults when the list was last
  // asked for (`showChanged`), as a set of dotted paths: taken then, not
  // followed, so a setting put back to its default stays listed (and new
  // edits don't rebuild the cards) until it's asked for again
  property var changedSet: ({})

  // Lists the settings changed from their defaults, as they are now
  function showChanged() {
    root.query = "";
    root.changedSet = root.nonDefaultPaths.reduce((set, path) => {
      set[path] = true;
      return set;
    }, {});
    root.changedOnly = true;
  }

  // Every default filled in, from the schema alone
  readonly property var defaults: SchemaValidation.applyDefaults({}, ConfigManager.configSchema)
  // The key paths the settings page has a row for (not `x-settings: false`)
  readonly property var _settingsPaths: SchemaLayout.rows(ConfigManager.configSchema, []).filter(row => row.kind !== "group").reduce((set, row) => {
    set[row.path.join(".")] = true;
    return set;
  }, {})
  // Key paths ("Appearance.font.size") of settings whose value in the
  // draft differs from the schema default, in the sections the page
  // shows; arrays count as one value
  readonly property var nonDefaultPaths: _diff(draft.local, root.defaults, []).filter(path => root._settingsPaths[path] === true && root._shownSections.includes(path.split(".")[0]))

  // The sections the page shows: some show only with a compositor or a
  // config mode (their `x-showIf`), which moves where a setting is
  readonly property var _shownSections: [].concat(...SchemaLayout.categories(ConfigManager.configSchema, root.showIfValue).map(category => category.sections))
  readonly property string _shownKey: root._shownSections.join(",")

  // Opens the overlay's settings page on a category (its sidebar name)
  function openCategory(name) {
    root.query = "";
    root.changedOnly = false;
    root.category = name;
    ShellManager.openOverlayPage("Settings");
  }

  // Opens the page on the card showing a setting (a key path, dotted or
  // an array: "Appearance.font.size"), or a section's or object's first
  // card ("BarStyle"), scrolls to it and outlines the setting's row. `link`:
  // followed from another page, which the navigator then offers to go back
  // to (ShellManager.followLink). False when no card shows it
  function openSetting(path, link) {
    const found = root.locate(path);
    if (!found) {
      console.warn(`SettingsManager: no settings card shows ${path}`);
      return false;
    }
    root.query = "";
    root.changedOnly = false;
    root.category = found.category;
    if (link === true)
      ShellManager.followLink("Settings");
    else
      ShellManager.openOverlayPage("Settings");
    root.jumpTo(found.key, found.row);
    return true;
  }

  // Where the page shows a setting (SchemaLayout.locate: { category, key,
  // title, row }, or null), remembered per path, since links ask for it
  // as they're drawn and it lays out the whole schema. Filled in place,
  // which doesn't notify (a binding asking would otherwise loop); a schema
  // reload, or a section showing or hiding, starts a new one, which does
  function locate(path) {
    const key = Array.isArray(path) ? path.join(".") : String(path);
    const located = root._located;
    if (!(key in located))
      located[key] = SchemaLayout.locate(ConfigManager.configSchema, key, root.showIfValue);
    return located[key];
  }
  property var _located: ({})
  on_ShownKeyChanged: root._located = {}
  property Connections _schemaWatch: Connections {
    target: ConfigManager
    function onConfigSchemaChanged() {
      root._located = {};
    }
  }

  // The jump the page hasn't made yet: { key, row } (`row` a setting's key
  // path to outline, or null for the card). Kept until the page has the
  // card laid out, so a jump made before the page is built still lands
  readonly property var pendingJump: root._pendingJump
  property var _pendingJump: null

  // The page scrolls to a card (by SchemaLayout group key), unfolding it
  // first; `unfolded` says it had to, so the page waits for it to open.
  // `row` (a key path): the row in it to outline
  signal jumpRequested(string key, bool unfolded)
  function jumpTo(key, row) {
    const unfolded = root.isCollapsed(key);
    if (unfolded)
      root.setCollapsed(key, false);
    root._pendingJump = {
      "key": key,
      "row": row ?? null
    };
    root.jumpRequested(key, unfolded);
  }

  // The page made the jump, or found it can't
  function jumpDone() {
    root._pendingJump = null;
  }

  // Settings cards the user folded, by SchemaLayout group key; saved in
  // state/settings.json so they stay folded across restarts
  property var collapsed: ({})
  readonly property var _state: StateManager.createStateHandler("settings")

  function isCollapsed(key) {
    return root.collapsed[key] === true;
  }

  // `keys`: one group key or a list of them
  function setCollapsed(keys, value) {
    const next = Object.assign({}, root.collapsed);
    for (const key of [].concat(keys)) {
      if (value)
        next[key] = true;
      else
        delete next[key];
    }
    root.collapsed = next;
    root._state.save({
      "collapsed": Object.keys(next)
    });
  }

  Component.onCompleted: {
    const saved = root._state.load({});
    root.collapsed = (saved.collapsed ?? []).reduce((all, key) => {
      all[key] = true;
      return all;
    }, {});
    // The icon folders, as the XDG icon spec looks them up: ~/.icons, then
    // each data dir's icons/
    const iconDirs = [Paths.homeDirectory + ".icons"].concat(Paths.dataSearchDirs.map(dir => dir + "/icons"));
    CommandManager.run(["sh", "-c", 'for d in "$@"; do for t in "$d"/*; do [ -d "$t/cursors" ] || [ -f "$t/manifest.hl" ] && basename "$t"; done; done | sort -u', "sh"].concat(iconDirs), (code, out) => root._cursorThemes = out.split("\n").filter(name => name !== "" && !name.startsWith(CursorThemeManager.companionPrefix)));
  }

  function _diff(local, saved, path) {
    const isObject = value => value !== null && typeof value === "object" && !Array.isArray(value);
    if (isObject(local) && isObject(saved)) {
      const keys = Object.keys(local).concat(Object.keys(saved).filter(key => !(key in local)));
      return [].concat(...keys.map(key => _diff(local[key], saved[key], path.concat(key))));
    }
    return JSON.stringify(local) === JSON.stringify(saved) ? [] : [path.join(".")];
  }

  function isChanged(path) {
    return root.changedPaths.includes(path.join("."));
  }

  // Whether anything under a path prefix (e.g. a section key) has changed
  function hasChangesUnder(prefix) {
    return root.changedPaths.some(changed => changed === prefix || changed.startsWith(prefix + "."));
  }

  function loadConfig() {
    draft.load();
  }

  // Loads the draft unless it holds unsaved edits (the page is rebuilt
  // whenever the overlay reopens)
  function ensureLoaded() {
    draft.loadIfStale();
  }

  function _setAt(object, path, value) {
    let cur = object;
    for (let i = 0; i < path.length - 1; i++) {
      if (typeof cur[path[i]] !== "object" || cur[path[i]] === null)
        cur[path[i]] = {};
      cur = cur[path[i]];
    }
    cur[path[path.length - 1]] = Utils.clone(value);
  }

  // The latest config with the draft's settings at these key paths on top
  function _merged(paths) {
    const merged = Utils.clone(ConfigManager.config);
    for (const path of paths)
      _setAt(merged, path, Utils.valueAt(draft.local, path));
    return merged;
  }

  // Sets one value by path (e.g. ["Appearance", "shape", "radius"]) and
  // shows it live.
  function setValue(path, value) {
    root.setValues([
      {
        "path": path,
        "value": value
      }
    ]);
  }

  // Sets several values ([{ path, value }]), shown live in one go
  function setValues(entries) {
    const previews = {};
    for (const entry of entries) {
      _setAt(draft.local, entry.path, entry.value);
      Object.assign(previews, _previewOf(entry.path, entry.value));
    }
    ConfigManager.setPreviews(previews);
    draft.changed();
  }

  // The settings this page shows live (ConfigManager.previews), as a set
  // of dotted paths
  property var _previewed: ({})

  // The previews that show `value` at `path` (path → value; undefined
  // clears one): none for `x-applyOnSave` settings (Hyprland's mode, which
  // can take over files), which wait in the draft until Save; cleared when
  // it's back as saved, unless one of this page's above it still shows
  // the edit; one set at a path drops this page's below it
  function _previewOf(path, value) {
    if (schemaAt(path)?.["x-applyOnSave"])
      return {};
    const key = path.join(".");
    const out = {};
    for (const shown of Object.keys(root._previewed).filter(shown => shown.startsWith(key + "."))) {
      out[shown] = undefined;
      delete root._previewed[shown];
    }
    const covered = Object.keys(root._previewed).some(shown => key.startsWith(shown + "."));
    if (!covered && Utils.deepEqual(value, Utils.valueAt(draft.saved, path))) {
      out[key] = undefined;
      delete root._previewed[key];
    } else {
      out[key] = value;
      root._previewed[key] = true;
    }
    return out;
  }

  // The draft was loaded again (saved, reset): nothing unsaved to show
  function _clearPreviews() {
    ConfigManager.setPreviews(Object.keys(root._previewed).reduce((out, key) => {
      out[key] = undefined;
      return out;
    }, {}));
    root._previewed = {};
  }

  // Puts the settings at these key paths back as saved (one card's
  // Discard)
  function discard(paths) {
    root.setValues(paths.map(path => ({
          "path": path,
          "value": Utils.clone(Utils.valueAt(draft.saved, path))
        })));
  }

  // Sets one value in the draft only (a text field being typed in), so
  // it shows as unsaved; setValue applies it
  function setDraftValue(path, value) {
    _setAt(draft.local, path, value);
    draft.changed();
  }

  // The schema of the setting at a key path
  function schemaAt(path) {
    const schema = ConfigManager.configSchema;
    let node = schema;
    for (const key of path)
      node = SchemaValidation.resolveRef(node?.properties?.[key], schema);
    return node;
  }

  // What a setting marked `x-inherit` (a dotted path) is while it's null:
  // the setting it follows, followed on while that is null too
  // (widgetRadius → Interface.radius → Appearance.shape.radius); null if
  // none is set
  function inheritedValue(fieldSchema) {
    let follows = fieldSchema?.["x-inherit"];
    for (let hops = 0; follows && hops < 8; hops++) {
      const value = root.configValueAt(follows) ?? null;
      if (value !== null)
        return value;
      follows = root.schemaAt(follows.split("."))?.["x-inherit"];
    }
    return null;
  }

  // The choices for a string setting (`enum` or `x-options`), else null
  function optionsFor(fieldSchema) {
    if (fieldSchema?.enum)
      return fieldSchema.enum;
    switch (fieldSchema?.["x-options"]) {
    case "screens":
      // `x-allScreens`: "*" puts the thing on every screen (bars)
      return ["", ...(fieldSchema["x-allScreens"] ? ["*"] : []), ...General.outputs.map(screen => screen.name)];
    case "chatProviders":
      return ChatConfig.providers.map(provider => provider.id);
    case "chatPresets":
      return ChatConfig.presets.map(preset => preset.name);
    case "colors":
      // `x-emptyLabel`: empty picks a color automatically; without it the
      // default comes first, the way back to it
      {
        const auto = !!fieldSchema["x-emptyLabel"];
        const first = auto ? "" : (fieldSchema.default ?? "");
        return (auto || first !== "" ? [first] : []).concat(Theme.baseColorNames.filter(name => name !== first));
      }
    case "cursorThemes":
      {
        const current = InputConfig.cursorTheme;
        const themes = root.cursorThemes;
        return ["", ...themes, ...(current && !themes.includes(current) ? [current] : [])];
      }
    case "languages":
      return I18n.languages.map(l => l.code);
    case "timezones":
      // Empty: the system's
      return ["", ...TimeZoneManager.zones];
    case "edgeMenus":
      return ["", ...EdgeMenusConfig.menus.map(menu => menu.id)];
    case "overlayPages":
      return ["", ...OverlayConfig.views.map(view => OverlayConfig.pageKey(view)).filter(key => key !== "")];
    case "notes":
      return ["", ...NotesManager.allNotes];
    case "calendars":
      // Those new events can go to
      return ["", ...CalendarManager.calendars.filter(calendar => calendar.writable).map(calendar => calendar.id)];
    }
    return null;
  }

  // Values offered as chips beside a free-text setting (`x-suggestions`):
  // it still takes anything typed
  function suggestionsFor(fieldSchema) {
    switch (fieldSchema?.["x-suggestions"]) {
    case "audioApps":
      // The apps playing sound now
      return AudioManager.playbackApps.map(app => app.name).filter((name, i, all) => all.indexOf(name) === i);
    }
    return [];
  }

  // --- Setting single values from outside the page (the launcher's /config) ---

  // Never offered, whatever the schema says: the bar and overlay editors
  // own these
  readonly property var _blockedPrefixes: ["Bars.items", "Overlay.items", "EdgeMenus"]

  // Every value the settings page shows, as { path, key, schema }, with
  // key the dotted path. `x-applyOnSave` settings are left out: they wait
  // for the page's Save for a reason (Hyprland's mode can take over files).
  // So are those the running compositor can't do (their `/$` showIf
  // conditions, SchemaLayout.compositorAllows: the Hyprland section
  // elsewhere); conditions on the config aren't, as /config sets them
  // whatever the rest says.
  readonly property var settingPaths: {
    const schema = ConfigManager.configSchema;
    if (!schema?.properties)
      return [];
    return SchemaLayout.rows(schema, []).filter(row => row.kind === "field" && !row.schema["x-applyOnSave"] && SchemaLayout.compositorAllows(schema, row.path, root.showIfValue)).map(row => ({
          path: row.path,
          key: row.path.join("."),
          schema: row.schema
        })).filter(entry => !root._blockedPrefixes.some(prefix => entry.key === prefix || entry.key.startsWith(prefix + ".")));
  }

  function settingFor(key) {
    const wanted = key.toLowerCase();
    return root.settingPaths.find(entry => entry.key.toLowerCase() === wanted) ?? null;
  }

  // Parses typed text for a setting: { value } or { error }
  function parseValue(schema, text) {
    const trimmed = text.trim();
    switch (schema.type) {
    case "boolean":
      {
        const word = trimmed.toLowerCase();
        if (["on", "true", "yes", "1"].includes(word))
          return {
            value: true
          };
        if (["off", "false", "no", "0"].includes(word))
          return {
            value: false
          };
        return {
          error: I18n.tr("Must be on or off")
        };
      }
    case "integer":
      {
        if (!/^-?\d+$/.test(trimmed))
          return {
            error: I18n.tr("Must be a whole number")
          };
        const number = parseInt(trimmed);
        if (schema.minimum !== undefined && number < schema.minimum)
          return {
            error: I18n.tr("Must be at least {0}", schema.minimum)
          };
        if (schema.maximum !== undefined && number > schema.maximum)
          return {
            error: I18n.tr("Must be at most {0}", schema.maximum)
          };
        return {
          value: number
        };
      }
    case "array":
      {
        const items = trimmed === "" ? [] : trimmed.split(",").map(item => item.trim()).filter(item => item !== "");
        const allowed = schema.items?.enum;
        const bad = allowed ? items.find(item => !allowed.includes(item)) : undefined;
        if (bad !== undefined)
          return {
            error: I18n.tr("\"{0}\" is not one of {1}", bad, allowed.join(", "))
          };
        return {
          value: items
        };
      }
    default:
      {
        const value = trimmed === "\"\"" ? "" : trimmed;
        if (schema.enum && !schema.enum.includes(value))
          return {
            error: I18n.tr("Must be one of {0}", schema.enum.join(", "))
          };
        return {
          value: value
        };
      }
    }
  }

  // Sets one setting and saves it straight away, leaving any unsaved edits
  // on the page alone. False if it's not a setting offered here, or the
  // save is rejected.
  function commitValue(key, value) {
    const entry = settingFor(key);
    if (!entry)
      return false;
    const next = Utils.clone(ConfigManager.config);
    _setAt(next, entry.path, value);
    if (!ConfigManager.commit(next, _takesOver([entry.path])))
      return false;
    ensureLoaded();
    return true;
  }

  // Sets config values by dotted path ({ "Apps.terminal": "foot" }) and
  // saves them at once; false if the result doesn't validate. For pages
  // that apply as they go (SettingRows), not the settings page's draft.
  function commitValues(values) {
    const next = Utils.clone(ConfigManager.config);
    for (const dottedPath of Object.keys(values))
      _setAt(next, dottedPath.split("."), values[dottedPath]);
    if (!ConfigManager.commit(next, _takesOver(Object.keys(values).map(dottedPath => dottedPath.split(".")))))
      return false;
    ensureLoaded();
    return true;
  }

  // A value anywhere in the running config, by dotted path
  // ("Workspaces.layout"): what an `x-showIf` key starting with `/` reads.
  // Two paths read the running compositor instead (schema-annotations.md ›
  // Compositor): `$compositor` (CompositorManager.kind) and
  // `$supports.<capability>` (true or false); `$distro` reads the
  // distribution family (DependencyManager.distro: "arch", "fedora", ""),
  // `$packaged` whether axiom is installed as a package
  // (Paths.packaged), `$clone` whether its tree is a git clone
  // (GreeterManager.report's `clone`; true until the first check).
  function configValueAt(dottedPath) {
    if (dottedPath === "$compositor")
      return CompositorManager.kind;
    if (dottedPath === "$distro")
      return DependencyManager.distro;
    if (dottedPath === "$packaged")
      return Paths.packaged;
    if (dottedPath === "$clone")
      return GreeterManager.report?.clone !== false;
    if (dottedPath.startsWith("$supports."))
      return CompositorManager.supports[dottedPath.slice(10)] === true;
    return Utils.valueAt(ConfigManager.live, dottedPath.split("."));
  }

  // A `/`-rooted `x-showIf` key's value (configValueAt)
  readonly property var showIfValue: key => root.configValueAt(key.slice(1))

  function valueOf(key) {
    const entry = settingFor(key);
    return entry ? Utils.valueAt(ConfigManager.live, entry.path) : undefined;
  }

  // Whether a save of these key paths is a takeover setting's own: it
  // names one (`x-takeover`), so axiom lets it change what it takes over
  function _takesOver(paths) {
    return paths.some(path => schemaAt(path)?.["x-takeover"] === true);
  }

  // Stays dirty if the save is rejected (invalid, or saves are blocked)
  function saveChanges() {
    // Diffed now, not `changedPaths`: Save first commits typed text, an
    // edit in place that `changedPaths` sees only next tick
    const changed = _diff(draft.local, draft.saved, []).map(path => path.split("."));
    if (!ConfigManager.commit(_merged(changed), _takesOver(changed)))
      return false;
    draft.load();
    return true;
  }

  function resetChanges() {
    draft.load();
  }
}
