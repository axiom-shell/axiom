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
// download goes through the daemon (community.fetch) and is checked
// against the catalog's sha256. Nothing here runs in the greeter.
QtObject {
  id: root

  readonly property bool enabled: CommunitySetups.enabled && !Paths.greeter
  // The catalog's setups (CommunityCatalog.parse), newest first; [] until
  // the gallery is first opened
  readonly property var setups: _setups
  // The catalog was read (from the network or, offline, the cache)
  readonly property bool loaded: _loaded
  readonly property bool loading: root._indexBusy
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
    if (!root.enabled || root._indexBusy)
      return;
    root._fetched = true;
    root._status = "";
    root._indexBusy = true;
    root._fetch([root._file(CommunitySetups.indexUrl, root._indexFile, "")], fetched => {
      root._indexBusy = false;
      if (fetched.ok[root._indexFile]) {
        if (root._readIndex(false))
          console.log("[CommunitySetupsManager] Catalog:", root._setups.length, "setups");
        return;
      }
      console.warn("[CommunitySetupsManager] Could not download the catalog:", fetched.failures.join("; "));
      root._status = root._loaded ? I18n.tr("Offline: showing the setups from last time") : I18n.tr("The catalog could not be downloaded");
    });
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
    if (root._screenshotBusy) {
      root._screenshotNext = id;
      return;
    }
    const dest = root._setupDir(id) + "screenshot" + CommunityCatalog.extension(setup.files.screenshot);
    root._screenshotBusy = true;
    root._fetch([root._file(root._url(setup.files.screenshot), dest, setup.files.screenshot.sha256)], fetched => {
      root._screenshotBusy = false;
      if (fetched.ok[dest]) {
        const screenshots = Object.assign({}, root._screenshots);
        screenshots[id] = "file://" + dest;
        root._screenshots = screenshots;
      }
      const next = root._screenshotNext;
      root._screenshotNext = "";
      if (next !== "")
        root.fetchScreenshot(next);
    });
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
    const downloads = [root._file(root._url(files.config), root._setupDir(id) + "config.json", files.config.sha256)];
    if (files.theme)
      downloads.push(root._file(root._url(files.theme), root._themeFile(id), files.theme.sha256));
    const wallpaper = withWallpaper && files.wallpaper ? root._wallpaperFile(setup) : "";
    if (wallpaper)
      downloads.push(root._file(root._url(files.wallpaper), wallpaper, files.wallpaper.sha256));
    root._applying = id;
    root._applyWallpaper = wallpaper;
    root._status = I18n.tr("Downloading \"{0}\"…", setup.title);
    root._fetch(downloads, fetched => root._finishApply(fetched.failures));
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
  // One download of each kind at a time
  property bool _indexBusy: false
  property bool _thumbsBusy: false
  property bool _screenshotBusy: false
  // The screenshot asked for during another's download ("" for none)
  property string _screenshotNext: ""
  // The wallpaper file the setup being applied downloads, set once
  // SavedConfigsManager has applied it ("" for none)
  property string _applyWallpaper: ""

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

  // Thumbnails not downloaded yet (the daemon keeps the cached ones)
  function _fetchThumbs() {
    if (root._thumbsBusy) {
      root._thumbsAgain = true;
      return;
    }
    if (root._setups.length === 0)
      return;
    const setups = root._setups;
    root._thumbsBusy = true;
    root._fetch(setups.map(setup => root._file(root._url(setup.files.thumb), root._thumbFile(setup), setup.files.thumb.sha256)), fetched => {
      root._thumbsBusy = false;
      const thumbs = {};
      for (const setup of setups) {
        const dest = root._thumbFile(setup);
        if (fetched.ok[dest])
          thumbs[setup.id] = "file://" + dest;
      }
      root._thumbs = thumbs;
      if (root._thumbsAgain) {
        root._thumbsAgain = false;
        root._fetchThumbs();
      }
    });
  }

  // One download of the daemon's: a File (sha256 "" for unchecked)
  function _file(url, dest, sha256) {
    return {
      "url": url,
      "dest": dest,
      "sha256": sha256
    };
  }

  // Downloads `files` (_file's), then calls done({ ok: { dest: true },
  // failures: ["dest: reason"] }); a call that failed as a whole fails
  // every file
  function _fetch(files, done) {
    BackendManager.call("community.fetch", {
      "files": files
    }, (error, result) => {
      const fetched = {
        "ok": {},
        "failures": []
      };
      if (error)
        fetched.failures.push(error.message);
      else
        for (const file of result.files) {
          if (file.error)
            fetched.failures.push(file.dest + ": " + file.error);
          else
            fetched.ok[file.dest] = true;
        }
      done(fetched);
    });
  }

  function _finishApply(failures) {
    const id = root._applying;
    const setup = root.setup(id);
    if (failures.length > 0 || !setup) {
      root._applying = "";
      root._status = I18n.tr("\"{0}\" could not be downloaded", setup?.title ?? id);
      console.warn("[CommunitySetupsManager] Download failed:", failures.join("; "));
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
