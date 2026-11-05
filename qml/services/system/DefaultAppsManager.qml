pragma Singleton
import QtQuick
import Quickshell
import qs.services.core

/*
 * The default apps, the freedesktop way (backend/internal/mimeapps): which
 * desktop entry opens each kind of file and link, from the mimeapps.list
 * files, and which terminal starts (xdg-terminals.list). For Settings ›
 * General › Default apps (`roles`, `setDefault`, `typeState` /
 * `setType` for one MIME type), and for opening anything with them
 * (`open(target, args)`: a role id, a URL or a path, through axiom's
 * apps.open, which uses the Apps section's command where it sets one).
 * What the keybinds run is `axiom open <role>` (Apps.terminalCommand …).
 */
Singleton {
  id: root

  // The roles the settings show, in order: their ids and labels (Go's
  // mimeapps.Roles has their types)
  // I18n.tr("Web browser") I18n.tr("Email") I18n.tr("Files") I18n.tr("Terminal")
  // I18n.tr("Text editor") I18n.tr("Images") I18n.tr("Video") I18n.tr("Music")
  // I18n.tr("Documents (PDF)") I18n.tr("Archives")
  readonly property var roleList: [
    {
      "id": "browser",
      "label": "Web browser",
      "icon": "public"
    },
    {
      "id": "mail",
      "label": "Email",
      "icon": "mail"
    },
    {
      "id": "fileManager",
      "label": "Files",
      "icon": "folder_open"
    },
    {
      "id": "terminal",
      "label": "Terminal",
      "icon": "terminal"
    },
    {
      "id": "textEditor",
      "label": "Text editor",
      "icon": "edit_note"
    },
    {
      "id": "images",
      "label": "Images",
      "icon": "image"
    },
    {
      "id": "video",
      "label": "Video",
      "icon": "movie"
    },
    {
      "id": "music",
      "label": "Music",
      "icon": "music_note"
    },
    {
      "id": "pdf",
      "label": "Documents (PDF)",
      "icon": "picture_as_pdf"
    },
    {
      "id": "archives",
      "label": "Archives",
      "icon": "folder_zip"
    }
  ]

  // role id -> { default, mixed, handlers: [{ id, name, icon, terminal }],
  // types }, {} until read
  readonly property var roles: _roles
  readonly property bool loaded: _loaded
  readonly property bool busy: _busy
  readonly property string error: _error

  function refresh() {
    BackendManager.call("apps.roles", {}, (error, result) => {
      if (!error)
        root._show(result);
    }, {
      "repeatable": true
    });
  }

  // A role's app (a desktop entry id), written to the user's mimeapps.list
  // (or xdg-terminals.list)
  function setDefault(role, id) {
    root._set(role, "", id);
  }

  // One MIME type's app (Other file types)
  function setType(mime, id) {
    root._set("", mime, id);
  }

  // `done({ default, handlers })` for one MIME type
  function typeState(mime, done) {
    BackendManager.call("apps.handlers", {
      "mime": String(mime ?? "")
    }, (error, result) => done(error ? {
        "default": "",
        "handlers": []
      } : result));
  }

  // Opens a role's app ("browser", "terminal", …), a URL or a path
  function open(target, args) {
    BackendManager.call("apps.open", {
      "target": String(target ?? ""),
      "args": args ?? []
    }, error => {
      if (error)
        console.warn("[DefaultAppsManager] opening", target, "failed:", error.message);
    });
  }

  // An entry's icon as a picture's path, for StyledComboEntry's `image`
  function iconOf(entry) {
    return entry?.icon ? AppIconManager.appIcon(entry.icon) : "";
  }

  function _set(role, mime, id) {
    if (root._busy)
      return;
    root._busy = true;
    root._error = "";
    BackendManager.call("apps.setDefault", {
      "role": String(role ?? ""),
      "mime": String(mime ?? ""),
      "id": String(id ?? "")
    }, (error, result) => {
      root._busy = false;
      if (error) {
        root._error = error.message;
        return;
      }
      root._show(result);
    });
  }

  function _show(list) {
    root._roles = list.reduce((out, role) => {
      out[role.id] = role;
      return out;
    }, {});
    root._loaded = true;
  }

  property var _roles: ({})
  property bool _loaded: false
  property bool _busy: false
  property string _error: ""
}
