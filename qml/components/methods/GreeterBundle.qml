pragma Singleton
import QtQuick

// The greeter's config, exported: GreeterManager writes it, `axiom
// greeter` loads it for the greeter (falling back to the install's
// snapshot, then the defaults). The greeter runs as another user, who
// can't read the user's config, so the user's axiom exports the part of it
// the greeter shows (the bundle, a partial format-2 config: the greeter
// fills the rest with schema defaults) to a folder it can read. Only data
// crosses: the greeter's own code turns it into anything it runs.
QtObject {
  id: root

  // The sections exported whole
  readonly property var sections: ["Greeter", "Appearance", "Interface", "General", "Weather"]

  // The bundle for `config`: its sections, the wallpapers renamed through
  // `wallpaperUrls` ({ the user's url: the bundle's copy }; a wallpaper
  // without a copy is left out, and the background falls back to its
  // color), the monitor layouts, and the Input options marked x-greeter
  // (`inputSchema`: Input's schema)
  function exportConfig(config, inputSchema, wallpaperUrls) {
    const out = {
      "format": config.format,
      "version": config.version
    };
    for (const section of root.sections)
      if (config[section] !== undefined)
        out[section] = JSON.parse(JSON.stringify(config[section]));
    const wallpaper = out.Appearance?.wallpaper;
    if (wallpaper) {
      const copy = url => wallpaperUrls?.[url] ?? "";
      wallpaper.file = copy(wallpaper.file);
      const perScreen = {};
      for (const monitor in wallpaper.perScreen ?? {}) {
        const url = copy(wallpaper.perScreen[monitor]);
        if (url)
          perScreen[monitor] = url;
      }
      wallpaper.perScreen = perScreen;
    }
    out.Compositor = {
      "mode": config.Compositor?.mode
    };
    out.Monitors = {
      "items": JSON.parse(JSON.stringify(config.Monitors?.items ?? []))
    };
    out.Input = root.greeterOptions(inputSchema, config.Input);
    return out;
  }

  // The x-greeter options of `values` (a section's, of `sectionSchema`):
  // in its groups (Input's keyboard, mouse, …) too
  function greeterOptions(sectionSchema, values) {
    const props = sectionSchema?.properties ?? {};
    const out = {};
    for (const key in props) {
      if (values?.[key] === undefined)
        continue;
      if (props[key]["x-greeter"] === true) {
        out[key] = JSON.parse(JSON.stringify(values[key]));
      } else if (props[key].type === "object" && props[key].properties) {
        const inner = root.greeterOptions(props[key], values[key]);
        if (Object.keys(inner).length > 0)
          out[key] = inner;
      }
    }
    return out;
  }

  // The wallpapers the bundle needs copies of: every url `config` uses
  function wallpaperSources(config) {
    const wallpaper = config?.Appearance?.wallpaper ?? {};
    const urls = [wallpaper.file].concat(Object.keys(wallpaper.perScreen ?? {}).map(monitor => wallpaper.perScreen[monitor]));
    return urls.filter((url, i) => !!url && urls.indexOf(url) === i);
  }
}
