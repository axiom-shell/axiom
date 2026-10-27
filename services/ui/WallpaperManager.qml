pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.components.methods
import qs.services.core

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
 */
Singleton {
  id: root

  readonly property string mode: Appearance.wallpaperMode

  // A pick by hand (a wallpaper picker, the launcher): `monitor`'s
  // wallpaper (the focused one's without one), or in "variant" mode the
  // variant's. Generates the themes from it.
  function pick(url, monitor, variant) {
    url = url.toString();
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
    ThemeManager.setWallpaperAndGenerate(url, monitor);
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
  // mode. Light/dark mode has none.
  function next() {
    if (root.mode === "variant") {
      console.log("[WallpaperManager] No next wallpaper in light/dark mode");
      return;
    }
    const list = root._wallpaperList();
    if (list.length === 0) {
      console.log("[WallpaperManager] No wallpapers in", Appearance.wallpaperPath);
      return;
    }
    ThemeManager.setLastRotated(Date.now());
    const order = Appearance.rotationOrder;
    const screens = General.outputs.map(screen => screen.name);
    const wallpapers = {};
    if (Appearance.rotationSameOnAll) {
      const url = Schedules.nextWallpaper(list, ThemeManager.wallpaperFor(General.primaryMonitor), order, [], Math.random());
      for (const monitor of screens)
        wallpapers[monitor] = url;
    } else {
      const taken = [];
      for (const monitor of screens) {
        const url = Schedules.nextWallpaper(list, ThemeManager.wallpaperFor(monitor), order, taken, Math.random());
        taken.push(url);
        wallpapers[monitor] = url;
      }
    }
    const changed = root.mode === "rotate" ? ThemeManager.showRotated(wallpapers) : ThemeManager.setWallpapers(wallpapers);
    // A generated theme follows on its own (ThemeManager.syncGeneratedTheme)
    if (!changed)
      ThemeManager.syncGeneratedTheme();
  }

  // --- The wallpaper folder (the onboarding's Look page) ---

  // Images in Appearance.wallpaperPath: -1 until checked (or while
  // checking), -2 when the folder doesn't exist
  property int folderImages: -1
  // Hyprland's own wallpapers (the first data dir's hypr/ with wall*.png),
  // offered as a folder to start from; "" until found
  readonly property string hyprlandWallpapers: _hyprlandWallpapers
  readonly property bool hasHyprlandWallpapers: _hyprlandWallpapers !== ""
  property string _hyprlandWallpapers: ""

  function checkFolder() {
    _folderCheck.running = false;
    _folderCheck.running = true;
  }

  // Creates the folder, opens it in the file manager and checks it again
  function createFolder() {
    CommandManager.runDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Appearance.wallpaperPath]);
    _recheck.restart();
  }

  function openFolder() {
    CommandManager.runDetached(["xdg-open", Appearance.wallpaperPath]);
  }

  property Process _folderCheck: Process {
    // Prints the image count (-2 without the folder), then the first
    // data dir's hypr/ holding Hyprland's wallpapers, if any
    command: ["sh", "-c", 'if [ -d "$1" ]; then find "$1" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.bmp" \\) | wc -l; else echo -2; fi; shift; for d in "$@"; do ls "$d"/hypr/wall*.png >/dev/null 2>&1 && { echo "$d/hypr"; break; }; done', "sh", Appearance.wallpaperPath].concat(Paths.dataSearchDirs)
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n").filter(line => line !== "");
        root.folderImages = parseInt(lines[0] ?? "-1");
        root._hyprlandWallpapers = lines[1] ?? "";
      }
    }
  }

  // mkdir runs detached: look again once it has
  property Timer _recheck: Timer {
    interval: 1000
    onTriggered: root.checkFolder()
  }

  // --- Private ---

  function _wallpaperList() {
    const model = ThemeManager.wallpaperModel;
    const list = [];
    for (let i = 0; i < model.count; i++)
      list.push(model.get(i, "fileUrl").toString());
    return list;
  }

  // --- Rotation ---
  onModeChanged: if (root.mode === "rotate")
    ThemeManager.setLastRotated(Date.now())

  property Timer _rotation: Timer {
    interval: 30000
    repeat: true
    running: root.mode === "rotate"
    onTriggered: {
      if (Date.now() - ThemeManager.lastRotated >= Appearance.rotationInterval)
        root.next();
    }
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

  property DailySchedule _themeSchedule: DailySchedule {
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
  }

  Component.onCompleted: {
    if (ThemeManager.lastRotated === 0)
      ThemeManager.setLastRotated(Date.now());
    // awww's daemon, unless it runs already (Appearance.wallpaperDaemon)
    if (Appearance.wallpaperDaemon && Appearance.wallpaperBackend === "awww")
      CommandManager.run(["sh", "-c", "command -v awww-daemon >/dev/null || exit 0; awww query >/dev/null 2>&1 || setsid -f awww-daemon >/dev/null 2>&1"]);
  }
}
