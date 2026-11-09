pragma Singleton
import QtQuick

// What the look shows at the moment, from what the user chose (config) and
// what changes on its own (runtime state ThemeManager keeps: the rotation's
// wallpapers, the theme schedule's variant). Changes on a timer never
// write the config, so it holds only choices. No file access, processes or
// services.
QtObject {
  id: root

  // The wallpapers shown, { wallpaper, wallpapers } (the primary's and the
  // fallback, and monitor → url):
  //   mode      Appearance.wallpaperMode
  //   fixed     the configured { wallpaper, wallpapers } (picked by hand)
  //   variants  { dark, light }: variant mode's, on every monitor
  //   dark      whether the shown theme is dark
  //   rotated   rotate mode's { wallpaper, wallpapers }, or null before
  //             the first rotation
  // A mode without its own wallpaper for a monitor shows the fixed one.
  function wallpapers(mode, fixed, variants, dark, rotated) {
    const own = {
      "wallpaper": fixed?.wallpaper ?? "",
      "wallpapers": Object.assign({}, fixed?.wallpapers ?? {})
    };
    if (mode === "variant") {
      const url = (dark ? variants?.dark : variants?.light) ?? "";
      return url ? {
        "wallpaper": url,
        "wallpapers": {}
      } : own;
    }
    if (mode === "rotate" && rotated)
      return {
        "wallpaper": rotated.wallpaper || own.wallpaper,
        "wallpapers": Object.assign(own.wallpapers, rotated.wallpapers ?? {})
      };
    return own;
  }

  // `monitor`'s wallpaper in `shown` (wallpapers()'s result), "" for none
  function wallpaperFor(shown, monitor) {
    return shown.wallpapers[monitor] || shown.wallpaper;
  }

  // The theme shown: the schedule's variant while the schedule is on and
  // it was set for the chosen theme (`override`: { for, name }, or null),
  // else the chosen one. Choosing another theme drops it until the next
  // edge of the schedule.
  function theme(chosen, scheduled, override) {
    return scheduled && override?.name && override.for === chosen ? override.name : chosen;
  }
}
