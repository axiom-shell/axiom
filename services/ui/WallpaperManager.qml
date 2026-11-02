pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.methods
import qs.services.core
import qs.services.compositor
import qs.services.session
import qs.services.system

/*
 * What changes the look on its own. ThemeManager shows it (activeTheme,
 * wallpaperFor) without writing the config, which keeps only what the
 * user picked:
 * - Appearance.wallpaperMode "rotate": a new wallpaper from the folder every
 *   `rotationInterval` ms (random or in order, one for all monitors or
 *   one each). A pick by hand shows until the next one. The time of the
 *   last change survives restarts.
 * - "variant": the light or dark wallpaper, whichever the active theme's
 *   variant is, on every monitor (ThemeManager derives it).
 * - Appearance.themeScheduled: the theme's light variant from `lightAt`, its
 *   dark one from `darkAt` (DailySchedule; a switch by hand lasts until the
 *   next of those).
 * A generated theme follows a wallpaper changed this way (the primary
 * monitor's); a pick by hand always generates, as the picker does.
 * Created from shell.qml's `_services`.
 *
 *   axiom ipc wallpaper next
 *   axiom ipc wallpaper random
 */
Singleton {
  id: root

  readonly property string mode: Appearance.wallpaperMode

  // A pick by hand (a wallpaper picker, the launcher): `monitor`'s
  // wallpaper (the focused one's without one), or in "variant" mode the
  // variant's. Generates the themes from it. `point` ({ x, y } in screen
  // units, optional): where it was clicked, for a transition that starts
  // where you click.
  function pick(url, monitor, variant, point) {
    url = url.toString();
    if (point)
      ThemeManager.startFrom(point);
    if (root.mode === "variant") {
      root.setVariantWallpaper(variant || (Appearance.darkMode ? "dark" : "light"), url);
      return;
    }
    if (root.mode === "rotate") {
      // Shown until the next rotation, which starts over from now
      ThemeManager.setLastRotated(Date.now());
      ThemeManager.showRotated({
        [ThemeManager.monitorFor(monitor)]: url
      });
      ThemeManager.generateThemesFromWallpaper(url);
      return;
    }
    ThemeManager.setWallpaper(url, monitor);
    ThemeManager.generateThemesFromWallpaper(url);
  }

  // The light or dark wallpaper ("dark" | "light"); ThemeManager shows it
  // when it's the current variant's, and the themes are generated from it
  function setVariantWallpaper(variant, url) {
    if (variant === (Appearance.darkMode ? "dark" : "light"))
      ThemeManager.generateThemesFromWallpaper(url.toString());
    const values = {};
    values["Appearance.wallpaper.variants." + variant] = url.toString();
    SettingsManager.commitValues(values);
  }

  // The next wallpaper of the folder now, and the timer starts over: the
  // rotation's in rotate mode, a new fixed one (asked for by hand) in fixed
  // mode, the shown variant's in light/dark mode (as `random` picks one).
  function next() {
    root.refresh(list => root._next(list));
  }

  // Moves on through `list`; whether anything shown changed
  function _next(list) {
    if (list.length === 0) {
      console.log("[WallpaperManager] No wallpapers in", root._listedPath);
      return false;
    }
    if (root.mode === "variant") {
      const variant = Appearance.darkMode ? "dark" : "light";
      const current = variant === "dark" ? Appearance.darkWallpaper : Appearance.lightWallpaper;
      root.setVariantWallpaper(variant, Schedules.nextWallpaper(list, current, Appearance.rotationOrder, [], Math.random()));
      return true;
    }
    ThemeManager.setLastRotated(Date.now());
    const order = Appearance.rotationOrder;
    const screens = General.outputs.map(screen => screen.name);
    const wallpapers = {};
    // Random order shuffles: each wallpaper once before any repeats
    let bag = ThemeManager.shuffleBag;
    const draw = (current, taken) => {
      if (order !== "random")
        return Schedules.nextWallpaper(list, current, order, taken, Math.random());
      const next = Schedules.shuffleWallpaper(list, bag, current, taken, Math.random());
      bag = next.bag;
      return next.url;
    };
    if (Appearance.rotationSameOnAll) {
      const url = draw(ThemeManager.wallpaperFor(General.primaryMonitor), []);
      for (const monitor of screens)
        wallpapers[monitor] = url;
    } else {
      const taken = [];
      for (const monitor of screens) {
        const url = draw(ThemeManager.wallpaperFor(monitor), taken);
        taken.push(url);
        wallpapers[monitor] = url;
      }
    }
    if (order === "random")
      ThemeManager.setShuffleBag(bag);
    const changed = root.mode === "rotate" ? ThemeManager.showRotated(wallpapers) : ThemeManager.setWallpapers(wallpapers);
    // A generated theme follows on its own (ThemeManager.syncGeneratedTheme)
    if (!changed)
      ThemeManager.syncGeneratedTheme();
    return changed;
  }

  // The next wallpaper (as next(), light/dark mode excepted), played with
  // `transition` (a WallpaperTransitions name) whatever is configured:
  // trying one out
  function preview(transition) {
    if (!WallpaperTransitions.names.includes(transition)) {
      console.warn("[WallpaperManager] No transition", transition, "- one of", WallpaperTransitions.names.join(", "));
      return;
    }
    if (root.mode === "variant") {
      console.log("[WallpaperManager] No next wallpaper in light/dark mode");
      return;
    }
    root.refresh(list => {
      ThemeManager.forceTransition(transition);
      // Nothing new to show: the next change plays the configured one
      if (!root._next(list))
        ThemeManager.forceTransition("");
    });
  }

  // A random wallpaper of the folder, picked by hand (for the focused
  // monitor, as `pick` does)
  function random() {
    root.refresh(list => root._random(list));
  }

  function _random(list) {
    if (list.length === 0) {
      console.log("[WallpaperManager] No wallpapers in", root._listedPath);
      return;
    }
    // From the shuffle's round, as the rotation draws
    const next = Schedules.shuffleWallpaper(list, ThemeManager.shuffleBag, ThemeManager.wallpaperFor(ThemeManager.monitorFor("")), [], Math.random());
    ThemeManager.setShuffleBag(next.bag);
    root.pick(next.url, "", "");
  }

  // --- The wallpaper folder (the onboarding's Look page) ---

  // Images in Appearance.wallpaperPath: -1 until checked (or while
  // checking), -2 when the folder doesn't exist
  property int folderImages: -1
  // The compositor's own wallpapers (the first data dir holding
  // CompositorManager.stockWallpapers), offered as a folder to start from;
  // "" until found, and for a compositor that ships none
  readonly property string compositorWallpapers: _compositorWallpapers
  property string _compositorWallpapers: ""

  // Prints the image count (-2 without the folder), then the first data
  // dir's folder holding the compositor's wallpapers, if any. Only the
  // latest check's answer counts
  function checkFolder() {
    const check = ++root._folderChecks;
    const stock = CompositorManager.stockWallpapers;
    CommandManager.run(["sh", "-c", 'if [ -d "$1" ]; then find "$1" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \\) | wc -l; else echo -2; fi; p=$2; shift 2; for d in "$@"; do ls "$d"/$p >/dev/null 2>&1 && { echo "$d/${p%/*}"; break; }; done', "sh", Appearance.wallpaperPath, stock].concat(stock !== "" ? Paths.dataSearchDirs : []), (code, stdout) => {
      if (check !== root._folderChecks)
        return;
      const lines = stdout.split("\n").filter(line => line !== "");
      root.folderImages = parseInt(lines[0] ?? "-1");
      root._compositorWallpapers = lines[1] ?? "";
    }, null, true);
  }
  property int _folderChecks: 0

  // Creates the folder, opens it in the file manager and checks it again
  function createFolder() {
    CommandManager.runDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Appearance.wallpaperPath]);
    _recheck.restart();
  }

  function openFolder() {
    CommandManager.runDetached(["xdg-open", Appearance.wallpaperPath]);
  }

  // mkdir runs detached: look again once it has
  property Timer _recheck: Timer {
    interval: 1000
    onTriggered: root.checkFolder()
  }

  // --- The wallpapers to pick from ---

  // The images of the folder's collection (Appearance.wallpaper.collection,
  // the folder itself when empty), with every folder under it when
  // subfolders is on: file URLs, by name. Listed by the daemon on start, on
  // a change of those settings, as the picker opens (refresh) and before
  // each rotation, so new files show up then
  readonly property var images: root._images
  // The folders under the wallpaper folder holding images, as paths inside
  // it ("trips", "trips/2024"): the collections to choose from
  readonly property var collections: root._collections
  readonly property string _listedPath: Appearance.wallpaperPath + (Appearance.wallpaperCollection ? "/" + Appearance.wallpaperCollection : "")
  readonly property var _extensions: ["jpg", "jpeg", "png", "bmp"]
  property var _images: []
  property var _collections: []
  property int _listings: 0
  property var _waiting: []
  on_ListedPathChanged: root.refresh()
  readonly property bool _subfolders: Appearance.wallpaperSubfolders
  on_SubfoldersChanged: root.refresh()

  // Lists the images again, then calls done(images). A listing asked for
  // meanwhile answers every caller waiting, with the newest list
  function refresh(done) {
    if (Paths.greeter)
      return;
    if (done)
      root._waiting.push(done);
    const listing = ++root._listings;
    BackendManager.call("file.list", {
      "path": root._listedPath,
      "extensions": root._extensions,
      "recursive": Appearance.wallpaperSubfolders
    }, (error, result) => {
      if (listing !== root._listings)
        return;
      // %, # and ? escaped first: a name holding # or ? isn't a fragment
      // or a query
      const images = error ? [] : result.files.map(path => Qt.resolvedUrl("file://" + path.replace(/[%#?]/g, encodeURIComponent)).toString());
      if (JSON.stringify(images) !== JSON.stringify(root._images))
        root._images = images;
      const waiting = root._waiting;
      root._waiting = [];
      waiting.forEach(fn => fn(root._images));
    });
    // The collections, from the whole folder
    BackendManager.call("file.list", {
      "path": Appearance.wallpaperPath,
      "extensions": root._extensions,
      "recursive": true
    }, (error, result) => {
      if (listing !== root._listings)
        return;
      const folders = error ? [] : result.folders;
      if (JSON.stringify(folders) !== JSON.stringify(root._collections))
        root._collections = folders;
    });
  }

  // --- Rotation ---
  onModeChanged: if (root.mode === "rotate")
    ThemeManager.setLastRotated(Date.now())

  // Whether the rotation waits (Appearance.wallpaper.rotation.pause): a
  // fullscreen window on any screen, the screen locked, on battery. Once
  // nothing holds it and its time has passed, it moves on at once.
  readonly property bool rotationHeld: (Appearance.rotationPauseFullscreen && General.outputs.some(screen => CompositorManager.hasFullscreen(screen.name))) || (Appearance.rotationPauseLocked && LockManager.builtinLocked) || (Appearance.rotationPauseBattery && BatteryManager.onBattery)
  onRotationHeldChanged: root._rotateIfDue()

  function _rotateIfDue() {
    if (root.mode === "rotate" && !root.rotationHeld && Date.now() - ThemeManager.lastRotated >= Appearance.rotationInterval)
      root.next();
  }

  property Timer _rotation: Timer {
    interval: 30000
    repeat: true
    running: root.mode === "rotate" && !root.rotationHeld
    onTriggered: root._rotateIfDue()
  }

  // --- Light and dark by time ---
  property var _pendingLight: null

  function _setLight(light) {
    // The theme list isn't read yet: once it is
    if (!ThemeManager.currentFamily) {
      root._pendingLight = light;
      return;
    }
    root._pendingLight = null;
    ThemeManager.followSchedule(light);
  }

  property Connections _families: Connections {
    target: ThemeManager
    function onCurrentFamilyChanged() {
      if (root._pendingLight !== null && ThemeManager.currentFamily)
        root._setLight(root._pendingLight);
    }
  }

  DailySchedule {
    id: _themeSchedule
    name: "theme"
    enabled: Appearance.themeScheduled
    startAt: Appearance.lightAt
    endAt: Appearance.darkAt
    onDue: light => root._setLight(light)
  }

  property IpcTarget _ipc: IpcTarget {
    target: "wallpaper"

    function next(): void {
      root.next();
    }

    function preview(transition: string): void {
      root.preview(transition);
    }

    function random(): void {
      root.random();
    }
  }

  // A reconnected daemon (a re-exec): the folder may have changed meanwhile
  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root.refresh();
    }
  }

  Component.onCompleted: {
    if (ThemeManager.lastRotated === 0)
      ThemeManager.setLastRotated(Date.now());
  }
}
