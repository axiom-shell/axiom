pragma Singleton
import QtQuick

// The community setups catalog (github.com/axiom-shell/community-setups,
// its `catalog` branch): reading its index.json, searching it, and where
// each file comes from and goes. The index is downloaded, so everything in
// it is checked before use: ids and file paths by pattern (a path never
// leaves its setup's folder), hashes by shape. No files, processes or
// services: CommunitySetupsManager downloads and applies.
QtObject {
  id: root

  // The index format this axiom reads (scripts/build_index.py's FORMAT)
  readonly property int format: 1
  readonly property var _id: /^[a-z0-9]+(-[a-z0-9]+)*$/
  readonly property var _sha: /^[0-9a-f]{64}$/
  readonly property var _compositors: ["hyprland", "niri", "sway"]

  // The setups of a parsed index.json, each checked and given
  // `compatible` (its config version is one `currentVersion` reads):
  // [{ id, title, author, description, about, tags, tested, fonts, theme,
  // compatible, wallpaper, page, files }], where files are { config,
  // theme?, wallpaper?, screenshot, thumb } of { path, sha256 }.
  // Malformed entries are left out; null when the index isn't one this
  // axiom reads.
  function parse(index, currentVersion) {
    if (!_isObject(index) || index.format !== root.format || !Array.isArray(index.setups))
      return null;
    const seen = {};
    const setups = [];
    for (const entry of index.setups) {
      const setup = root._setup(entry, currentVersion);
      if (setup && !seen[setup.id]) {
        seen[setup.id] = true;
        setups.push(setup);
      }
    }
    return setups;
  }

  function _setup(entry, currentVersion) {
    if (!_isObject(entry) || typeof entry.id !== "string" || !root._id.test(entry.id) || entry.id.length > 40)
      return null;
    const files = _isObject(entry.files) ? entry.files : {};
    const file = key => root._file(files[key], entry.id);
    const config = file("config");
    const screenshot = file("screenshot");
    const thumb = file("thumb");
    if (!config || !screenshot || !thumb || !Number.isInteger(entry.configVersion))
      return null;
    const checked = {
      "config": config,
      "screenshot": screenshot,
      "thumb": thumb
    };
    for (const key of ["theme", "wallpaper"]) {
      if (files[key] !== undefined) {
        const optional = file(key);
        if (!optional)
          return null;
        checked[key] = optional;
      }
    }
    const strings = value => Array.isArray(value) ? value.filter(item => typeof item === "string") : [];
    const text = value => typeof value === "string" ? value : "";
    const wallpaper = _isObject(entry.wallpaper) ? entry.wallpaper : null;
    return {
      "id": entry.id,
      "title": text(entry.title) || entry.id,
      "author": text(entry.author),
      "description": text(entry.description),
      "about": root._inertMarkdown(text(entry.about)),
      "tags": strings(entry.tags),
      "tested": strings(entry.tested).filter(name => root._compositors.includes(name)),
      "fonts": strings(entry.fonts),
      "theme": text(entry.theme),
      "compatible": entry.configVersion >= 1 && entry.configVersion <= currentVersion,
      "wallpaper": checked.wallpaper && wallpaper ? {
        "license": text(wallpaper.license),
        "source": text(wallpaper.source),
        "credit": text(wallpaper.credit)
      } : null,
      "page": /^https:\/\/github\.com\//.test(text(entry.page)) ? entry.page : "",
      "files": checked
    };
  }

  // A file entry inside setups/<id>/, or null
  function _file(value, id) {
    if (!_isObject(value) || typeof value.path !== "string" || typeof value.sha256 !== "string")
      return null;
    const prefix = "setups/" + id + "/";
    const rest = value.path.slice(prefix.length);
    if (!value.path.startsWith(prefix) || !/^[A-Za-z0-9_-][A-Za-z0-9._-]*(\/[A-Za-z0-9_-][A-Za-z0-9._-]*)?$/.test(rest) || !root._sha.test(value.sha256))
      return null;
    return {
      "path": value.path,
      "sha256": value.sha256
    };
  }

  // A file's URL: its path relative to the index's
  function fileUrl(indexUrl, file) {
    return String(indexUrl).replace(/[^/]*$/, "") + file.path;
  }

  // A file's extension, with the dot ("" for none)
  function extension(file) {
    const match = file.path.match(/(\.[A-Za-z0-9]+)$/);
    return match ? match[1].toLowerCase() : "";
  }

  // The setups matching every word of `text` (in the title, author,
  // description, tags or theme) and having every tag of `tags`, best
  // matches first (newest first between equals)
  function search(setups, text, tags) {
    const words = String(text ?? "").toLowerCase().split(/\s+/).filter(word => word !== "");
    const wanted = tags ?? [];
    const scored = [];
    setups.forEach((setup, order) => {
      if (!wanted.every(tag => setup.tags.includes(tag)))
        return;
      const fields = [setup.title, setup.author, setup.description, setup.theme].concat(setup.tags);
      let total = 0;
      for (const word of words) {
        const best = Math.max(...fields.map(field => Search.score(field, word)));
        if (best === 0)
          return;
        total += best;
      }
      scored.push({
        "setup": setup,
        "score": total,
        "order": order
      });
    });
    return scored.sort((a, b) => b.score - a.score || a.order - b.order).map(entry => entry.setup);
  }

  // Every tag the setups use, the most used first, then by name
  function tags(setups) {
    const counts = {};
    for (const setup of setups)
      for (const tag of setup.tags)
        counts[tag] = (counts[tag] ?? 0) + 1;
    return Object.keys(counts).sort((a, b) => counts[b] - counts[a] || a.localeCompare(b));
  }

  // The setup's fonts not among `families` (Qt.fontFamilies())
  function missingFonts(setup, families) {
    const installed = families.map(family => family.toLowerCase());
    return setup.fonts.filter(font => !installed.includes(font.toLowerCase()));
  }

  // Markdown from the catalog, made safe to render: raw HTML shows as
  // text and an image becomes a link, so showing it loads nothing
  function _inertMarkdown(text) {
    return text.replace(/</g, "&lt;").replace(/!\[/g, "[");
  }

  function _isObject(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
}
