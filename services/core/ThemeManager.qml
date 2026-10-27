pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.system

/* ThemeManager owns the active theme's data (loaded from its file, watched,
 * with defaults for what it leaves out), the theme lists, theme generation
 * from a wallpaper, the wallpaper itself, and re-theming integrated tools.
 * The choice of theme and wallpapers is config (Appearance.theme,
 * fixedWallpaper(s)), persisted through ConfigManager. What changes on its
 * own (the light/dark schedule's variant, the rotation's wallpapers, the
 * light/dark wallpapers) is shown without touching the config: activeTheme
 * and wallpaperFor() are what's showing (ShownLook), and the runtime part
 * is kept in state/look.json.
 *
 * In the greeter (Paths.greeter) it only reads: the active theme is the
 * theme.json beside the greeter's config (the bundle's, what the user's
 * theme was when it was exported, or the install's snapshot when the
 * config came from there), and nothing is generated, linked or run. */
QtObject {
  id: root

  //=========================================================================
  // Public Models & State
  //=========================================================================
  readonly property FolderListModel wallpaperModel: FolderListModel {
    folder: Paths.greeter ? "" : "file://" + Appearance.wallpaperPath
    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.bmp"]
    showDirs: false
  }
  // One entry per theme, a dark/light pair being one theme:
  // [{ label, dark, light, darkPreview, lightPreview, shared, generated,
  // community }] (ThemeFamilies.build), where dark/light are Appearance.theme
  // names ("" for a variant the theme doesn't have) and the previews are that
  // variant's _preview (or null). A family's extra darks (Tokyo Storm) are
  // families of their own sharing its light. Stock themes first, then
  // community setups' palettes, then generated ones.
  readonly property var themeFamilies: _families
  // The family Appearance.theme belongs to, or null; a shared light's is
  // the family it was switched to from
  readonly property var currentFamily: ThemeFamilies.current(themeFamilies, Appearance.theme, root._look.lightFrom ?? "")
  readonly property bool isGenerating: _generating !== ""
  // The theme list's groups ("builtin", "imported", "generated") folded shut
  readonly property var foldedGroups: root._look.foldedGroups ?? []

  // The active theme's JSON ({ name, variant, paired, colors, semantic }),
  // read through config/Theme
  readonly property var currentTheme: _theme
  // The theme showing: Appearance.theme, or the variant the light/dark
  // schedule last switched it to. Read from the config itself: the
  // Appearance reader's darkMode reads currentTheme, which loads from this.
  // reads: Appearance.theme.name, Appearance.theme.schedule.enabled
  readonly property string activeTheme: {
    const theme = ConfigManager.config.Appearance.theme;
    return Paths.greeter ? theme.name : ShownLook.theme(theme.name, theme.schedule.enabled, root._look.theme ?? null);
  }
  // The wallpapers showing ({ wallpaper, wallpapers }): the fixed ones, the
  // rotation's or the light/dark ones, by Appearance.wallpaper.mode
  readonly property var shownWallpapers: ShownLook.wallpapers(Paths.greeter ? "fixed" : Appearance.wallpaperMode, {
    "wallpaper": Appearance.fixedWallpaper,
    "wallpapers": Appearance.fixedWallpapers
  }, {
    "dark": Appearance.darkWallpaper,
    "light": Appearance.lightWallpaper
  }, Appearance.darkMode, root._look.rotated ?? null)
  // The primary monitor's (the lockscreen's)
  readonly property string wallpaper: root.wallpaperFor(General.primaryMonitor)
  function wallpaperFor(monitor) {
    return ShownLook.wallpaperFor(root.shownWallpapers, monitor);
  }
  // config/json/theme-defaults.json: fallback palette and semantic maps,
  // shared with the generated themes (axiom's theme.generate)
  readonly property var defaults: _defaults

  signal generationFailed(string errorText)
  onGenerationFailed: errorText => NotificationManager.sendNotification("axiom", I18n.tr("Failed to generate themes"), I18n.tr("There was an error while processing the wallpaper. Details: {0}", errorText))

  //=========================================================================
  // Public Functions
  //=========================================================================

  // `themeName` as Appearance.theme names it (generated ones "generated/…").
  // A choice by hand outlasts the schedule's variant until its next edge.
  function applyTheme(themeName) {
    if (!themeName)
      return;
    if (root._look.theme)
      root._saveLook({
        "theme": null
      });
    if (Appearance.theme === themeName)
      return;
    ConfigManager.setTheme(themeName);
  }

  // A family's variant for the current light/dark mode, or the one it has
  function applyFamily(family) {
    const target = Appearance.darkMode ? (family.dark || family.light) : (family.light || family.dark);
    root._rememberFamily(family, target);
    applyTheme(target);
  }

  // Sets the wallpaper, then generates themes from it
  function setWallpaperAndGenerate(wallpaperUrl, monitor) {
    setWallpaper(wallpaperUrl.toString(), monitor);
    generateThemesFromWallpaper(wallpaperUrl);
  }

  // `monitor`, or the focused monitor without one
  function monitorFor(monitor) {
    return monitor || (CompositorManager.focusedOutput || General.primaryMonitor);
  }

  // Sets `monitor`'s fixed wallpaper in the config (the focused monitor's
  // without one). The primary monitor's is also Appearance.fixedWallpaper,
  // the fallback for monitors without their own.
  function setWallpaper(wallpaperUrl, monitor) {
    if (!wallpaperUrl)
      return;
    const target = root.monitorFor(monitor);
    ConfigManager.setWallpaper(wallpaperUrl, target, target === General.primaryMonitor);
  }

  // Sets several monitors' fixed wallpapers at once ({ monitor: url }), with
  // one save; true if any changed
  function setWallpapers(wallpapers) {
    const primary = General.primaryMonitor;
    const changed = Object.keys(wallpapers).filter(monitor => wallpapers[monitor] && (Appearance.fixedWallpapers[monitor] !== wallpapers[monitor] || (monitor === primary && Appearance.fixedWallpaper !== wallpapers[monitor])));
    if (changed.length === 0)
      return false;
    ConfigManager.setWallpapers(changed.reduce((map, monitor) => {
      map[monitor] = wallpapers[monitor];
      return map;
    }, {}), primary);
    return true;
  }

  // Shows wallpapers ({ monitor: url }) as the rotation's, until the next
  // one, without touching the config; true if any changed
  function showRotated(wallpapers) {
    const primary = General.primaryMonitor;
    const changed = Object.keys(wallpapers).filter(monitor => wallpapers[monitor] && root.wallpaperFor(monitor) !== wallpapers[monitor]);
    if (changed.length === 0)
      return false;
    const rotated = root._look.rotated ?? {};
    const next = {
      "wallpaper": rotated.wallpaper ?? "",
      "wallpapers": Object.assign({}, rotated.wallpapers ?? {})
    };
    for (const monitor of changed) {
      next.wallpapers[monitor] = wallpapers[monitor];
      if (monitor === primary)
        next.wallpaper = wallpapers[monitor];
    }
    root._saveLook({
      "rotated": next
    });
    return true;
  }

  // When the rotation last moved on (ms since the epoch; 0 for never)
  readonly property real lastRotated: root._look.lastRotated ?? 0
  function setLastRotated(time) {
    root._saveLook({
      "lastRotated": time
    });
  }

  // awww needs telling; the built-in backend (shell/Wallpaper) follows
  // wallpaperFor(). Either way the primary's is linked to
  // ~/.current_wallpaper. Only _applyShown calls it.
  function _showWallpaper(url, monitor, primary) {
    if (Paths.greeter)
      return;
    const path = url.replace("file://", "");
    if (Appearance.wallpaperBackend === "awww")
      Quickshell.execDetached([Paths.scriptsPath + "setWallpaper.sh", path, monitor, primary ? "1" : "0"]);
    else if (primary)
      Quickshell.execDetached(["ln", "-sf", path, Quickshell.env("HOME") + "/.current_wallpaper"]);
  }

  // Generated themes are named by style, not wallpaper, so each run
  // overwrites the last and a config only records the theme's name. When
  // the active one was made from another wallpaper than the configured one
  // (a snapshot restored over a newer generation), generate it again: the
  // file watch then reloads the colors and runs the integrations.
  function syncGeneratedTheme() {
    if (Paths.greeter || !root.activeTheme.startsWith("generated/") || !root.wallpaper)
      return;
    // Already on its way
    if (isGenerating && (root._generating === root.wallpaper || root._pendingGeneration === root.wallpaper))
      return;
    const wanted = decodeURIComponent(root.wallpaper.replace("file://", ""));
    if (root.currentTheme?.generated?.wallpaper === wanted)
      return;
    console.log("[ThemeManager] Generated theme is from", root.currentTheme?.generated?.wallpaper ?? "no wallpaper", "- regenerating for", wanted);
    generateThemesFromWallpaper(root.wallpaper);
  }

  // The wallpaper URL being generated from (axiom's theme.generate), or ""
  property string _generating: ""
  // A request made while a run is going replaces any earlier one and runs
  // after it, so the last wallpaper asked for is the one generated
  property string _pendingGeneration: ""

  function generateThemesFromWallpaper(wallpaperUrl) {
    // The one running is the latest wanted again (Dark, Light, Dark):
    // nothing after it
    if (isGenerating && wallpaperUrl.toString() === root._generating) {
      root._pendingGeneration = "";
      return;
    }
    if (isGenerating) {
      console.log("[ThemeManager] Generation already in progress; queued:", wallpaperUrl.toString());
      root._pendingGeneration = wallpaperUrl.toString();
      return;
    }
    console.log("[ThemeManager] Generating themes from", wallpaperUrl.toString());
    // Decoded first: a malformed URL throws here, not with a run marked going
    const wallpaper = decodeURIComponent(wallpaperUrl.toString().replace("file://", ""));
    root._generating = wallpaperUrl.toString();
    BackendManager.call("theme.generate", {
      "wallpaper": wallpaper
    }, (error, result) => {
      if (error) {
        console.error("[ThemeManager] Theme generation failed:", error.message);
        root.generationFailed(error.message);
      } else {
        console.log("[ThemeManager] Generated", result.files.length, "themes");
        root._reloadAllThemes();
        // The watch misses a file that didn't exist when it started
        root._reloadTheme();
      }
      root._generating = "";
      const next = root._pendingGeneration;
      root._pendingGeneration = "";
      if (next)
        Qt.callLater(() => root.generateThemesFromWallpaper(next));
    });
  }

  // Shows the current theme's light (or dark) variant for the light/dark
  // schedule, leaving the chosen one in the config
  function followSchedule(light) {
    const target = light ? currentFamily?.light : currentFamily?.dark;
    if (!target) {
      console.log("[ThemeManager] No", light ? "light" : "dark", "variant of", Appearance.theme);
      return;
    }
    root._saveLook({
      "theme": target === Appearance.theme ? null : {
        "for": Appearance.theme,
        "name": target
      }
    });
  }

  // Switches to the current theme's light (or dark) variant, if it has one
  function setLightMode(light) {
    const target = light ? currentFamily?.light : currentFamily?.dark;
    if (!target) {
      console.log("[ThemeManager] No", light ? "light" : "dark", "variant of", Appearance.theme);
      return;
    }
    root._rememberFamily(currentFamily, target);
    applyTheme(target);
  }

  // Folds a theme list group shut, or open again
  function toggleGroup(group) {
    const folded = root.foldedGroups.includes(group) ? root.foldedGroups.filter(name => name !== group) : root.foldedGroups.concat([group]);
    root._saveLook({
      "foldedGroups": folded
    });
  }

  function toggleDarkMode() {
    setLightMode(Appearance.darkMode);
  }

  // Runs the enabled integrations (scripts/theme_<key>.sh, one per
  // ThemeIntegrations switch) for a theme; `keys` limits it to those (none:
  // all of them)
  function themeIntegrations(themeName = root.activeTheme, keys = []) {
    if (Paths.greeter)
      return;
    const themePath = Paths.themeFile(themeName);
    const all = keys.length === 0;
    for (let i = 0; i < root.integrations.length; i++) {
      const key = root.integrations[i];
      const process = root._integrationRunner.objectAt(i);
      if (!ThemeIntegrations[key] || !process || (!all && !keys.includes(key)))
        continue;
      // A busy one runs again for the latest theme once it's done, or a
      // quick light-dark-light would leave it on the middle one
      if (process.running) {
        process.queued = themePath;
        continue;
      }
      process.command = [Paths.scriptsPath + "theme_" + key + ".sh", themePath];
      process.running = true;
    }
    if (all)
      root._themed = root._enabledIntegrations;
  }

  // The switched-on integrations (keys, in schema order), and those as of the
  // last full run (null before the first, while config and theme load):
  // one switched on since is themed right away, not at the next theme
  // change
  // reads: ThemeIntegrations.* (as ThemeIntegrations[key])
  readonly property var _enabledIntegrations: root.integrations.filter(key => ThemeIntegrations[key] === true)
  property var _themed: null
  on_EnabledIntegrationsChanged: {
    if (root._themed === null)
      return;
    const added = root._enabledIntegrations.filter(key => !root._themed.includes(key));
    root._themed = root._enabledIntegrations;
    if (added.length > 0)
      root.themeIntegrations(root.activeTheme, added);
  }

  //=========================================================================
  // Private Implementation
  //=========================================================================
  Component.onCompleted: {
    // What the initializer loaded, so the first change check is a no-op
    root._themeContent = FileManager.read(root._themeUrl(root._themeName)) ?? "";
    root._loadedName = root._themeName;
    // Keep the initial value but drop its binding, which would re-read the
    // file on every config save (mid-write during a generation);
    // _reloadTheme owns it from here
    const initial = root._theme;
    root._theme = initial;
    if (Paths.greeter)
      return;
    _reloadAllThemes();
    // Anything shown changed while qs wasn't running (a light/dark
    // wallpaper, a monitor), and a generated theme that isn't there yet
    Qt.callLater(root._applyShown);
  }

  // --- What's showing ---
  // state/look.json: { theme: { for, name } (the schedule's variant of the
  // chosen theme, or null), rotated: { wallpaper, wallpapers },
  // lastRotated, applied: { monitors, primary } (what the backend was last
  // told) }. The greeter keeps none.
  readonly property var _lookState: StateManager.createStateHandler("look")
  property var _look: Paths.greeter ? ({}) : root._lookState.load({})

  // Picking a family's light remembers its dark, so a light several
  // families share stays in the one it was picked from
  function _rememberFamily(family, target) {
    root._picked = target;
    if (target === family.light && family.dark && (root._look.lightFrom ?? "") !== family.dark)
      root._saveLook({
        "lightFrom": family.dark
      });
  }

  // The theme the last pick set (_rememberFamily). Appearance.theme
  // changing to any other (a restored or applied config, the settings
  // field) forgets lightFrom, which only that pick's light belongs to.
  property string _picked: ""
  property Connections _themeChange: Connections {
    target: Appearance

    function onThemeChanged() {
      if (Appearance.theme !== root._picked && root._look.lightFrom)
        root._saveLook({
          "lightFrom": null
        });
    }
  }

  function _saveLook(changes) {
    if (Paths.greeter)
      return;
    root._look = Object.assign({}, root._look, changes);
    root._lookState.save(root._look);
  }

  // Tells the backend about each monitor whose wallpaper changed (or that
  // just connected), and brings a generated theme in line with the
  // primary's. Runs on any change of what's shown: a pick, a rotation, a
  // light/dark switch, a mode switch, a restored config.
  readonly property string _shownKey: Paths.greeter ? "" : JSON.stringify([root.shownWallpapers, General.primaryMonitor, General.outputs.map(screen => screen.name)])
  on_ShownKeyChanged: Qt.callLater(root._applyShown)

  function _applyShown() {
    if (Paths.greeter)
      return;
    const before = root._look.applied ?? {};
    const after = {
      "monitors": {},
      "primary": before.primary ?? ""
    };
    const primary = General.primaryMonitor;
    for (const screen of General.outputs) {
      const url = root.wallpaperFor(screen.name);
      if (!url)
        continue;
      const isPrimary = screen.name === primary;
      if (before.monitors?.[screen.name] !== url || (isPrimary && after.primary !== url))
        root._showWallpaper(url, screen.name, isPrimary);
      after.monitors[screen.name] = url;
      if (isPrimary)
        after.primary = url;
    }
    if (!Utils.deepEqual(after, before))
      root._saveLook({
        "applied": after
      });
    root.syncGeneratedTheme();
  }

  // --- Active theme ---
  // Loaded eagerly so config/Theme never sees an empty theme
  property var _defaults: _readDefaults()
  property var _theme: _parseTheme(FileManager.read(_themeUrl(root.activeTheme)), root.activeTheme)
  property string _themeContent: ""
  // The theme _theme and _themeContent are from
  property string _loadedName: ""
  readonly property string _themeName: root.activeTheme
  on_ThemeNameChanged: _reloadTheme()

  property FileView _themeWatch: FileView {
    path: root._themeUrl(root._themeName)
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload();
      root._reloadTheme();
    }
  }

  function _themeUrl(name) {
    // The greeter's theme comes from where its config did: the bundle,
    // else the install's snapshot (whose code is this copy's)
    if (Paths.greeter)
      return ConfigManager.greeterSource === "bundle" ? "file://" + Paths.greeterBundlePath + "theme.json" : Paths.greeterFallbackUrl + "theme.json";
    return "file://" + Paths.themeFile(name);
  }

  function _readDefaults() {
    try {
      return JSON.parse(FileManager.read("file://" + Paths.resourcePath + "json/theme-defaults.json"));
    } catch (e) {
      console.error("[ThemeManager] Could not read theme-defaults.json:", e);
      return {
        "colors": {},
        "semantic": {
          "dark": {},
          "light": {}
        }
      };
    }
  }

  // A theme file's JSON, or null if it's empty or broken
  function _tryParse(content) {
    if (!content)
      return null;
    try {
      return JSON.parse(content);
    } catch (e) {
      return null;
    }
  }

  // A theme file's JSON, or the default palette if it's missing or broken,
  // in the variant its name suggests (so a missing light theme doesn't
  // turn Appearance.darkMode on)
  function _parseTheme(content, name) {
    const parsed = _tryParse(content);
    if (parsed)
      return parsed;
    // The greeter's theme is a file beside its config, whatever the name
    console.error("[ThemeManager]", content ? "Failed to parse theme:" : "Theme not found:", Paths.greeter ? _themeUrl(name) : name);
    const defaults = root._defaults ?? _readDefaults();
    const variant = /light$/i.test(name ?? "") ? "light" : "dark";
    return {
      "name": "Default (fallback)",
      "variant": variant,
      "colors": defaults.colors,
      "semantic": defaults.semantic[variant]
    };
  }

  // Reloads the active theme when its name or its file's contents change,
  // and re-themes the integrated tools (not on startup)
  function _reloadTheme() {
    const name = _themeName;
    const content = FileManager.read(_themeUrl(name)) ?? "";
    if (name === _loadedName && content === _themeContent)
      return;
    // Mid-write (an editor truncates a file before writing it, and the
    // watch fires in between) or not generated yet: keep what's showing.
    // The next change, or the end of the generation, reads it whole.
    // Falling back here would flash the default palette and flip darkMode.
    if (!_tryParse(content) && (name === _loadedName || isGenerating)) {
      console.log("[ThemeManager]", name, "is empty or partly written; keeping the current colors");
      return;
    }
    _loadedName = name;
    _themeContent = content;
    _theme = _parseTheme(content, name);
    if (Paths.greeter)
      return;
    // A generated theme that isn't there yet (a migrated name, a cleared
    // folder) is made, and themes the tools once it's read
    if (!content) {
      syncGeneratedTheme();
      return;
    }
    // Deferred: a restored config changes the theme and the integration
    // switches at once, and ThemeIntegrations may not have caught up yet
    Qt.callLater(root.themeIntegrations);
  }

  // --- Paths and Models ---
  readonly property string _themesPath: "file://" + Paths.themePath
  readonly property string _generatedThemesPath: "file://" + Paths.generatedThemesPath
  readonly property string _communityThemesPath: "file://" + Paths.communityThemesPath

  // Each folder's themes, [{ name, label, variant, paired }], combined
  // into _families once any folder has been scanned
  property var _stockThemes: []
  property var _generatedThemes: []
  property var _communityThemes: []
  property var _families: []

  // --- Integration processes ---

  // The ThemeIntegrations switches, in schema order: one per
  // scripts/theme_<key>.sh
  readonly property var integrations: {
    const props = ConfigManager.configSchema.properties.ThemeIntegrations.properties;
    return Object.keys(props).filter(key => props[key].type === "boolean");
  }

  // An integration's name (its schema title, untranslated)
  function integrationTitle(key) {
    return ConfigManager.configSchema.properties.ThemeIntegrations.properties[key]?.title ?? key;
  }

  // The commands any of which shows an integration's app is installed: its
  // key unless listed here, none for ones every desktop has
  readonly property var _integrationCommands: ({
      "gtk": [],
      // qt*ct, or a KDE app (which reads the KDE scheme without them)
      "qt": ["qt6ct", "qt5ct", "okular", "dolphin", "kate", "kwrite", "gwenview", "konsole", "ark", "spectacle", "systemsettings"],
      "helix": ["hx", "helix"],
      "vscode": ["code", "codium"],
      "zed": ["zed", "zeditor", "zedit", "dev.zed.Zed"],
      "vesktop": ["vesktop", "dev.vencord.Vesktop", "equibop", "discord"],
      "firefox": ["firefox", "librewolf", "zen-browser", "zen", "floorp", "waterfox", "org.mozilla.firefox", "io.gitlab.librewolf-community", "app.zen_browser.zen", "one.ablaze.floorp", "net.waterfox.waterfox"]
    })
  function integrationCommands(key) {
    return root._integrationCommands[key] ?? [key];
  }

  // One process per integration, each running its script
  property Instantiator _integrationRunner: Instantiator {
    model: root.integrations
    delegate: Process {
      id: integration
      required property string modelData
      // Reported once both the exit and the end of stderr are in, in
      // whichever order they come
      property int _exitCode: -1
      property bool _stderrDone: false
      // A theme asked for while it was running, run next
      property string queued: ""

      function _report() {
        if (_exitCode < 0 || !_stderrDone)
          return;
        // A failure logs all of stderr; a success only its "Warning:" lines
        const text = errors.text.trim();
        const shown = _exitCode === 0 ? text.split("\n").filter(line => line.startsWith("Warning:")).join("\n") : text || "exited with " + _exitCode;
        if (shown)
          console.warn("[ThemeManager] theme_" + modelData + ".sh:", shown);
        if (queued) {
          command = [Paths.scriptsPath + "theme_" + modelData + ".sh", queued];
          queued = "";
          Qt.callLater(() => integration.running = true);
        }
      }

      onRunningChanged: if (running) {
        _exitCode = -1;
        _stderrDone = false;
      }
      onExited: exitCode => {
        _exitCode = exitCode;
        _report();
      }
      stdout: StdioCollector {}
      stderr: StdioCollector {
        id: errors
        onStreamFinished: {
          integration._stderrDone = true;
          integration._report();
        }
      }
    }
  }

  // --- Theme List Loading ---

  // Rescans the theme folders; each rebuilds the families when it's read
  function _reloadAllThemes() {
    _defaultThemeLoader.folder = "";
    _generatedThemeLoader.folder = "";
    _communityThemeLoader.folder = "";
    _defaultThemeLoader.folder = _themesPath;
    _generatedThemeLoader.folder = _generatedThemesPath;
    _communityThemeLoader.folder = _communityThemesPath;
  }

  // Rescans the community setups' palettes, after one is installed
  // (CommunitySetupsManager)
  function reloadCommunityThemes() {
    _communityThemeLoader.folder = "";
    _communityThemeLoader.folder = _communityThemesPath;
  }

  // A scanned folder's themes, parsed for their name, variant and pair.
  // `prefix` makes each name what Appearance.theme calls it. A community
  // palette is one theme on its own: its `paired` names a stock theme,
  // never one beside it.
  function _readThemes(loader, prefix) {
    const themes = [];
    for (let i = 0; i < loader.count; i++) {
      const fileName = loader.get(i, "fileName");
      if (fileName === "theme.schema.json")
        continue;
      try {
        const json = JSON.parse(FileManager.read("file://" + loader.get(i, "filePath")));
        themes.push({
          "name": prefix + loader.get(i, "fileBaseName"),
          "label": json.name || loader.get(i, "fileBaseName"),
          "variant": json.variant === "light" ? "light" : "dark",
          "paired": json.paired && prefix !== "community/" ? prefix + json.paired : "",
          "preview": root._preview(json)
        });
      } catch (e) {
        console.warn("[ThemeManager] Skipping unreadable theme", fileName, e);
      }
    }
    return themes;
  }

  // A theme's look for the theme list: { background, foreground, accent,
  // colors: base08-base0E }, filling what it omits from theme-defaults.json
  function _preview(json) {
    const variant = json.variant === "light" ? "light" : "dark";
    const colors = Object.assign({}, root._defaults.colors, json.colors ?? {});
    const semantic = Object.assign({}, root._defaults.semantic?.[variant] ?? {}, json.semantic ?? {});
    const resolve = key => colors[semantic[key]] ?? "";
    return {
      "background": resolve("background") || colors.base00,
      "foreground": resolve("foreground") || colors.base05,
      "accent": resolve("accent") || colors.base0D,
      "colors": ["base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E"].map(name => colors[name])
    };
  }

  function _rebuildFamilies() {
    root._families = ThemeFamilies.build(root._stockThemes, false).concat(ThemeFamilies.build(root._communityThemes, false, true), ThemeFamilies.build(root._generatedThemes, true));
    console.log("[ThemeManager] Themes:", root._families.map(family => family.label).join(", "));
  }

  // Ready is reported once before the rows arrive, then again with them.
  // Directories are hidden (showDirs): themes are files.
  property FolderListModel _defaultThemeLoader: FolderListModel {
    nameFilters: ["*.json"]
    showDirs: false
    onStatusChanged: if (status === FolderListModel.Ready && count > 0) {
      root._stockThemes = root._readThemes(root._defaultThemeLoader, "");
      root._rebuildFamilies();
    }
  }

  property FolderListModel _generatedThemeLoader: FolderListModel {
    nameFilters: ["*.json"]
    showDirs: false
    onStatusChanged: if (status === FolderListModel.Ready && count > 0) {
      root._generatedThemes = root._readThemes(root._generatedThemeLoader, "generated/");
      root._rebuildFamilies();
    }
  }

  property FolderListModel _communityThemeLoader: FolderListModel {
    nameFilters: ["*.json"]
    showDirs: false
    onStatusChanged: if (status === FolderListModel.Ready && count > 0) {
      root._communityThemes = root._readThemes(root._communityThemeLoader, "community/");
      root._rebuildFamilies();
    }
    // Its last palette deleted, the count drops to 0 with no Ready after
    // it; a rescan drops it to 0 too, just before the rows come back
    onCountChanged: if (count === 0 && root._communityThemes.length > 0)
      root._communityEmptied.restart()
  }

  // An emptied community folder, believed once it stays empty
  property Timer _communityEmptied: Timer {
    interval: 1000
    onTriggered: if (root._communityThemeLoader.count === 0 && root._communityThemes.length > 0) {
      root._communityThemes = [];
      root._rebuildFamilies();
    }
  }
}
