pragma Singleton
import QtQuick

// Where axiom keeps what it writes (XDG base directories). Every path ends
// in a slash. ConfigManager resolves these; Paths hands
// them out. Also where to look for data others installed (searchDirs).
QtObject {
  id: root

  // An XDG base directory: the variable when it's an absolute path (the
  // spec ignores relative ones), else HOME's fallback; no trailing slash
  function _base(env, name, fallback) {
    const value = String(env[name] ?? "").trim();
    if (value.startsWith("/"))
      return value.replace(/(.)\/+$/, "$1");
    return String(env.HOME ?? "").replace(/\/+$/, "") + "/" + fallback;
  }

  // The XDG layout for `env` ({ HOME, XDG_CONFIG_HOME, XDG_STATE_HOME,
  // XDG_DATA_HOME, XDG_CACHE_HOME }): { config, state, ui, data, notes,
  // generatedThemes, communityThemes, cache }. `state` is axiom's own state
  // folder (secrets, chats, generated configs), `ui` the small JSON state
  // files, `notes` the default notes folder, `communityThemes` the palettes
  // community setups bring, `cache` what can be downloaded again
  function xdg(env) {
    const config = root._base(env, "XDG_CONFIG_HOME", ".config") + "/axiom/";
    const state = root._base(env, "XDG_STATE_HOME", ".local/state") + "/axiom/";
    const data = root._base(env, "XDG_DATA_HOME", ".local/share") + "/axiom/";
    return {
      "config": config,
      "state": state,
      "ui": state + "ui/",
      "data": data,
      "notes": data + "notes/",
      "generatedThemes": state + "themes/",
      "communityThemes": data + "themes/",
      "cache": root._base(env, "XDG_CACHE_HOME", ".cache") + "/axiom/"
    };
  }

  // Where to look for installed data (`env` { HOME, XDG_DATA_HOME,
  // XDG_DATA_DIRS }), in the XDG lookup order, most important first:
  // XDG_DATA_HOME, then XDG_DATA_DIRS' absolute entries, or the spec's
  // /usr/local/share and /usr/share when it has none (NixOS keeps nothing
  // in /usr/share). No trailing slashes, no repeats.
  function searchDirs(env) {
    const system = String(env.XDG_DATA_DIRS ?? "").split(":").map(dir => dir.trim()).filter(dir => dir.startsWith("/")).map(dir => dir.replace(/(.)\/+$/, "$1"));
    const dirs = [root._base(env, "XDG_DATA_HOME", ".local/share")].concat(system.length > 0 ? system : ["/usr/local/share", "/usr/share"]);
    return dirs.filter((dir, i) => dirs.indexOf(dir) === i);
  }
}
