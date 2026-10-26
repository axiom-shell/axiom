pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

// The community setups gallery (github.com/axiom-shell/community-setups):
// downloads the catalog (CommunitySetups.indexUrl) when the gallery is
// opened, never before, and the setups' thumbnails and screenshots into
// the cache; applies one through SavedConfigsManager.applyShared (its
// look only, after a "before-<id>" backup), first installing its palette
// as the theme "community/<id>" and, when asked, its wallpaper; the result
// is saved as the snapshot "community-<id>", the active one. Every
// download goes through scripts/community_fetch.sh and is checked against
// the catalog's sha256. Nothing here runs in the greeter.
QtObject {
  id: root

  readonly property bool enabled: CommunitySetups.enabled && !Paths.greeter
  // The catalog's setups (CommunityCatalog.parse), newest first; [] until
  // the gallery is first opened
  readonly property var setups: _setups
  // The catalog was read (from the network or, offline, the cache)
  readonly property bool loaded: _loaded
  readonly property bool loading: root._indexFetch.running
  // { id: file URL } of the thumbnails downloaded so far
  readonly property var thumbs: _thumbs
  // { id: file URL } of the full screenshots downloaded (fetchScreenshot)
  readonly property var screenshots: _screenshots
  // The setup being downloaded and applied, "" for none
  readonly property string applying: _applying
  // The setup whose saved config ("community-<id>", saved by the apply,
  // SavedConfigsManager.activeSource) is the active one, unchanged, "" for
  // none: switching to another, changing the look or saving over it ends it
  readonly property string applied: {
    const source = SavedConfigsManager.activeSource;
    return source !== "" && SavedConfigsManager.active === _snapshotPrefix + source && !SavedConfigsManager.modified ? source : "";
  }
  // What happened last, for the gallery
  readonly property string status: _status

  // Reads the cached catalog and refreshes it once per session: the
  // gallery calls this when it's shown
  function open() {
    if (!root.enabled)
      return;
    // Read once, here rather than in a binding (it would loop on itself)
    if (root._fontFamilies === null)
      root._fontFamilies = Qt.fontFamilies();
    if (!root._loaded)
      root._readIndex(true);
    if (!root._fetched)
      root.refresh();
  }

  // Downloads the catalog again, then any thumbnails not cached yet
  function refresh() {
    if (!root.enabled || root._indexFetch.running)
      return;
    root._fetched = true;
    root._status = "";
    root._indexFetch.launch([root._fetchScript, CommunitySetups.indexUrl, root._indexFile, "-"]);
  }

  function setup(id) {
    return root._setups.find(entry => entry.id === id) ?? null;
  }

  // The setups matching `text` and every tag of `tags`
  function search(text, tags) {
    return CommunityCatalog.search(root._setups, text, tags);
  }

  // Every tag the setups use, the most used first
  function tags() {
    return CommunityCatalog.tags(root._setups);
  }

  // The setup's fonts that aren't installed (known once the gallery opened)
  function missingFonts(setup) {
    return root._fontFamilies === null ? [] : CommunityCatalog.missingFonts(setup, root._fontFamilies);
  }

  // Downloads a setup's full screenshot (into `screenshots`); asked for
  // during another's download, it follows that one
  function fetchScreenshot(id) {
    const setup = root.setup(id);
    if (!setup || root._screenshots[id])
      return;
    if (root._screenshotFetch.running) {
      root._screenshotNext = id;
      return;
    }
    const dest = root._setupDir(id) + "screenshot" + CommunityCatalog.extension(setup.files.screenshot);
    root._screenshotId = id;
    root._screenshotDest = dest;
    root._screenshotFetch.launch([root._fetchScript, root._url(setup.files.screenshot), dest, setup.files.screenshot.sha256]);
  }

  // Downloads a setup and applies it: its palette is installed first, its
  // wallpaper (with `withWallpaper`) set once the config is
  function apply(id, withWallpaper) {
    const setup = root.setup(id);
    if (!root.enabled || !setup || root._applying !== "")
      return;
    if (!setup.compatible) {
      root._status = I18n.tr("\"{0}\" needs a newer axiom", setup.title);
      return;
    }
    const files = setup.files;
    const args = [root._fetchScript, root._url(files.config), root._setupDir(id) + "config.json", files.config.sha256];
    if (files.theme)
      args.push(root._url(files.theme), root._themeFile(id), files.theme.sha256);
    const wallpaper = withWallpaper && files.wallpaper ? root._wallpaperFile(setup) : "";
    if (wallpaper)
      args.push(root._url(files.wallpaper), wallpaper, files.wallpaper.sha256);
    root._applying = id;
    root._applyWallpaper = wallpaper;
    root._status = I18n.tr("Downloading \"{0}\"…", setup.title);
    root._applyFetch.launch(args);
  }

  // The issue form that submits a setup, its title filled in (attachments
  // can't be)
  function submitUrl(title) {
    return "https://github.com/axiom-shell/community-setups/issues/new?template=01-submit-setup.yml&title=" + encodeURIComponent("Setup: " + title);
  }

  // -- Private --
  property var _setups: []
  property bool _loaded: false
  // The catalog was asked for this session
  property bool _fetched: false
  property var _thumbs: ({})
  property var _screenshots: ({})
  property string _applying: ""
  property string _status: ""
  property var _fontFamilies: null
  // A newer catalog came while the thumbnails were downloading: once more
  // after that run
  property bool _thumbsAgain: false
  // The screenshot being downloaded (its setup and file), and the one
  // asked for meanwhile ("" for none)
  property string _screenshotId: ""
  property string _screenshotDest: ""
  property string _screenshotNext: ""
  // The wallpaper file the setup being applied downloads, set once
  // SavedConfigsManager has applied it ("" for none)
  property string _applyWallpaper: ""

  readonly property string _fetchScript: Paths.scriptsPath + "community_fetch.sh"
  readonly property string _indexFile: Paths.communityCachePath + "index.json"
  readonly property string _snapshotPrefix: "community-"

  function _setupDir(id) {
    return Paths.communityCachePath + "setups/" + id + "/";
  }

  function _themeFile(id) {
    return Paths.communityThemesPath + id + ".json";
  }

  function _thumbFile(setup) {
    return Paths.communityCachePath + "thumbs/" + setup.id + CommunityCatalog.extension(setup.files.thumb);
  }

  function _wallpaperFile(setup) {
    return Paths.userDataPath + "wallpapers/" + setup.id + CommunityCatalog.extension(setup.files.wallpaper);
  }

  function _url(file) {
    return CommunityCatalog.fileUrl(CommunitySetups.indexUrl, file);
  }

  // Reads the downloaded (or, `cached`, the last) index.json
  function _readIndex(cached) {
    const content = FileManager.read("file://" + root._indexFile);
    if (!content)
      return false;
    let setups = null;
    try {
      setups = CommunityCatalog.parse(JSON.parse(content), ConfigManager.currentVersion);
    } catch (e) {
      console.warn("[CommunitySetupsManager] Could not parse the catalog:", e);
    }
    if (setups === null) {
      if (!cached)
        root._status = I18n.tr("The catalog isn't one this axiom can read. Update axiom.");
      return false;
    }
    root._setups = setups;
    root._loaded = true;
    root._fetchThumbs();
    return true;
  }

  // Thumbnails not downloaded yet (the script keeps the cached ones)
  function _fetchThumbs() {
    if (root._thumbFetch.running) {
      root._thumbsAgain = true;
      return;
    }
    if (root._setups.length === 0)
      return;
    const args = [root._fetchScript];
    for (const setup of root._setups)
      args.push(root._url(setup.files.thumb), root._thumbFile(setup), setup.files.thumb.sha256);
    root._thumbFetch.launch(args);
  }

  // The script's "ok DEST" lines, as { dest: true }
  function _okDests(text) {
    return text.split("\n").filter(line => line.startsWith("ok ")).reduce((map, line) => {
      map[line.slice(3)] = true;
      return map;
    }, {});
  }

  function _failures(text) {
    return text.split("\n").filter(line => line.startsWith("fail ")).map(line => line.slice(5));
  }

  function _finishApply(ok, output) {
    const id = root._applying;
    const setup = root.setup(id);
    if (!ok || !setup) {
      root._applying = "";
      root._status = I18n.tr("\"{0}\" could not be downloaded", setup?.title ?? id);
      console.warn("[CommunitySetupsManager] Download failed:", root._failures(output).join("; "));
      return;
    }
    if (setup.files.theme)
      ThemeManager.reloadCommunityThemes();
    if (!SavedConfigsManager.applyShared(id, root._setupDir(id) + "config.json", setup.title, root._snapshotPrefix + id)) {
      root._applying = "";
      root._status = SavedConfigsManager.status;
    }
  }

  // Sets the setup's wallpaper on every monitor, as the fixed one, in one
  // save. It changes no takeover setting: sent without `takeover`, so the
  // config cloned before axiom's own write after the apply (the compositor
  // mode kept on leaving its hold) can't put the stale one back
  function _setWallpaper(url) {
    const config = Utils.clone(ConfigManager.config);
    const wallpaper = config.Appearance.wallpaper;
    wallpaper.mode = "fixed";
    wallpaper.file = url;
    for (const output of General.outputs)
      wallpaper.perScreen[output.name] = url;
    if (!ConfigManager.commit(config, false))
      console.warn("[CommunitySetupsManager] Could not set the wallpaper", url);
  }

  property Connections _savedConfigs: Connections {
    target: SavedConfigsManager

    function onApplied(name) {
      if (name !== root._applying || name === "")
        return;
      const setup = root.setup(name);
      if (root._applyWallpaper)
        root._setWallpaper("file://" + root._applyWallpaper);
      root._applying = "";
      root._status = SavedConfigsManager.status;
      console.log("[CommunitySetupsManager] Applied", name, setup?.title ?? "");
    }

    function onApplyFailed(name) {
      if (name !== root._applying || name === "")
        return;
      root._applying = "";
      root._status = SavedConfigsManager.status;
    }
  }

  // Each a CommunityFetch: its `done` hands over the script's lines
  property CommunityFetch _indexFetch: CommunityFetch {
    onDone: output => {
      if (root._okDests(output)[root._indexFile]) {
        if (root._readIndex(false))
          console.log("[CommunitySetupsManager] Catalog:", root._setups.length, "setups");
        return;
      }
      console.warn("[CommunitySetupsManager] Could not download the catalog:", root._failures(output).join("; ") || "community_fetch.sh failed");
      root._status = root._loaded ? I18n.tr("Offline: showing the setups from last time") : I18n.tr("The catalog could not be downloaded");
    }
  }

  property CommunityFetch _thumbFetch: CommunityFetch {
    onDone: output => {
      const ok = root._okDests(output);
      const thumbs = {};
      for (const setup of root._setups) {
        const dest = root._thumbFile(setup);
        if (ok[dest])
          thumbs[setup.id] = "file://" + dest;
      }
      root._thumbs = thumbs;
      if (root._thumbsAgain) {
        root._thumbsAgain = false;
        root._fetchThumbs();
      }
    }
  }

  property CommunityFetch _screenshotFetch: CommunityFetch {
    onDone: output => {
      if (root._okDests(output)[root._screenshotDest]) {
        const screenshots = Object.assign({}, root._screenshots);
        screenshots[root._screenshotId] = "file://" + root._screenshotDest;
        root._screenshots = screenshots;
      }
      const next = root._screenshotNext;
      root._screenshotNext = "";
      if (next !== "")
        root.fetchScreenshot(next);
    }
  }

  property CommunityFetch _applyFetch: CommunityFetch {
    onDone: output => root._finishApply(output.trim() !== "" && root._failures(output).length === 0, output)
  }

  property IpcTarget _ipc: IpcTarget {
    target: "community"
    enabled: root.enabled

    // Downloads the catalog again
    function refresh(): void {
      root.refresh();
    }

    // The catalog's setups, one "id: title" per line
    function list(): string {
      root.open();
      return root._setups.map(setup => setup.id + ": " + setup.title).join("\n");
    }

    // Applies a setup by id, without its wallpaper
    function apply(id: string): void {
      root.apply(id, false);
    }
  }
}
