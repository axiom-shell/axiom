pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services.core

// Translation and locale for the shell's text (General.language).
//
// English is the source language: write strings in English, inline, as
// I18n.tr("Text"). Each other language is one file, config/i18n/<code>.json:
//   { "_meta": { "name": "日本語", "locale": "ja_JP", "formats": { ... } },
//     "strings": { "English text": "translation", ... } }
// Dropping in a file adds the language to the settings (x-options
// "languages"); a string with no entry falls back to English. Placeholders
// {0}, {1}, ... take the extra arguments, so dynamic text stays one
// translatable string: I18n.tr("{0} updates", count).
// Settings titles/descriptions come from the schema and are translated by
// the settings UI, so they need no code. scripts/check_i18n.py lists
// missing/unused entries (--fill adds the missing ones, empty) and keeps the
// empty dictionary a new language is copied from, config/i18n/template/.
//
// tr() and formatDate() read the language, so bindings using them update
// when it (or the active dictionary file) changes.
QtObject {
  id: root

  readonly property string language: General.language

  // [{ code, name, locale }], English first, then one per dictionary file
  property var languages: [root._english]
  readonly property var current: root.languages.find(l => l.code === root.language) ?? root._english
  // For day/month names and date formats
  readonly property var locale: Qt.locale(root.current.locale)

  function tr(text, ...args) {
    let result = (root.current.code !== "en" && root._strings[text]) || text;
    args.forEach((arg, i) => result = result.split(`{${i}}`).join(String(arg)));
    return result;
  }

  // Qt date format strings, with names (ddd, MMMM, AP) in the shell's language
  function formatDate(date, format) {
    return date.toLocaleString(root.locale, format);
  }

  // AM or PM for `date`'s hour, in the shell's language (午前/午後 in
  // Japanese), for clocks that set it apart from the time
  function meridiem(date) {
    return date.getHours() < 12 ? root.locale.amText : root.locale.pmText;
  }

  // An epoch-ms timestamp as a short time ago: "now", "5m", "3h", "2d"
  // Keys, for scripts/check_i18n.py: I18n.tr("now") I18n.tr("{0}m") I18n.tr("{0}h") I18n.tr("{0}d")
  function formatRelative(epochMs) {
    const seconds = Math.max(0, Math.floor((Date.now() - epochMs) / 1000));
    if (seconds < 60)
      return root.tr("now");
    if (seconds < 3600)
      return root.tr("{0}m", Math.floor(seconds / 60));
    if (seconds < 86400)
      return root.tr("{0}h", Math.floor(seconds / 3600));
    return root.tr("{0}d", Math.floor(seconds / 86400));
  }

  // A named date format in the shell's language: the dictionary's
  // _meta.formats entry, else the English one below
  function dateFormat(name) {
    return root.current.formats?.[name] ?? root._formats[name] ?? name;
  }

  function languageName(code) {
    return root.languages.find(l => l.code === code)?.name ?? code;
  }

  // -- Private --
  readonly property var _english: ({
      "code": "en",
      "name": "English",
      "locale": "en_US"
    })
  readonly property var _formats: ({
      "longDate": "dddd, d MMMM",
      "mediumDate": "MMM d, yyyy",
      "shortDate": "ddd d MMM",
      "monthYear": "MMMM yyyy",
      "fullDate": "dddd, MMMM d, yyyy",
      // A file's time (saved configs)
      "dateTime": "MMM d, yyyy HH:mm",
      "time24": "HH:mm",
      "time12": "h:mm AP",
      // The bar clock (s: with seconds)
      "clock24": "HH:mm",
      "clock24s": "HH:mm:ss",
      "clock12": "hh:mm ap",
      "clock12s": "hh:mm:ss ap"
    })
  readonly property string _dir: Quickshell.shellPath("config/i18n")
  property var _strings: ({})

  function _read(path) {
    try {
      const content = FileManager.read(path);
      if (content === null)
        throw new Error("unreadable");
      return JSON.parse(content);
    } catch (e) {
      console.warn("[I18n] Could not read dictionary:", path, e);
      return null;
    }
  }

  function _scan() {
    const found = [root._english];
    for (let i = 0; i < root._files.count; i++) {
      const code = root._files.get(i, "fileBaseName");
      const meta = root._read(`${root._dir}/${code}.json`)?._meta ?? {};
      found.push({
        "code": code,
        "name": meta.name ?? code,
        "locale": meta.locale ?? code,
        "formats": meta.formats ?? {}
      });
    }
    root.languages = found;
  }

  property FolderListModel _files: FolderListModel {
    folder: "file://" + root._dir
    nameFilters: ["*.json"]
    showDirs: false
    onCountChanged: root._scan()
  }

  // The active dictionary, reloaded when the file is edited
  property FileView _dictionary: FileView {
    path: root.current.code !== "en" ? `${root._dir}/${root.current.code}.json` : ""
    watchChanges: true
    onFileChanged: reload()
    onPathChanged: {
      if (path === "")
        root._strings = {};
    }
    onLoaded: {
      try {
        root._strings = JSON.parse(text()).strings ?? {};
        console.log(`[I18n] ${root.current.name}: ${Object.keys(root._strings).length} strings`);
      } catch (e) {
        console.warn("[I18n] Invalid dictionary:", path, e);
      }
    }
  }
}
