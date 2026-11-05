pragma Singleton
import QtQuick
import Quickshell
import qs.config
import qs.services.core
import qs.services.system
import qs.services.apps

/*
 * The user's own account, for Settings › General › Account and the lock
 * screen's picture: their login and real name, picture and whether
 * they're an administrator (account.get: AccountsService, else
 * /etc/passwd and ~/.face; backend/internal/account), and the changes a
 * user makes to it: the picture (`setIcon`, a file picked; "" removes it),
 * the real name (`setRealName`, AccountsService only) and the password
 * (`changePassword`, through passwd in axiom; the passwords go in the call
 * and to passwd's terminal only). Never in greeter mode: the greeter shows
 * the users GreetdManager lists.
 */
Singleton {
  id: root

  readonly property string login: _account.login ?? (Quickshell.env("USER") ?? "")
  readonly property string realName: _account.realName ?? ""
  // The picture's path, "" for none
  readonly property string icon: _account.icon ?? ""
  // The picture to show: a new URL each time it changes, so an Image
  // reloads the same path (~/.face) instead of keeping the old one
  readonly property string iconUrl: root.icon !== "" ? "file://" + root.icon + "?" + root._iconRevision : ""
  readonly property bool admin: _account.admin === true
  // AccountsService answered: the picture reaches the login screen, and
  // the real name can be changed
  readonly property bool accountsService: _account.accounts === true
  readonly property bool loaded: _account.login !== undefined

  // A change is waiting (polkit's prompt included)
  readonly property bool busy: _busy
  // The last change's error ("" when it worked)
  readonly property string error: _error

  function refresh() {
    if (Paths.greeter)
      return;
    BackendManager.call("account.get", {}, (error, result) => {
      if (!error)
        root._show(result);
    }, {
      "repeatable": true
    });
  }

  // Asks for a picture (the desktop's file picker), then sets it
  function pickIcon() {
    FilePickerManager.pick(root, I18n.tr("Choose a picture"), {
      "filter": I18n.tr("Images") + ":*.png *.jpg *.jpeg *.webp *.gif *.bmp",
      "start": "~/Pictures"
    }, path => root.setIcon(path), () => root._error = I18n.tr("No file picker could be opened"));
  }

  function setIcon(path) {
    root._change("account.setIcon", {
      "path": Paths.expandHome(String(path ?? ""))
    });
  }

  function setRealName(name) {
    root._change("account.setRealName", {
      "name": String(name ?? "")
    });
  }

  // `done({ ok, reason, message })`: reason "wrong" | "weak" | "mismatch" |
  // "failed", message passwd's (translated where axiom knows it)
  // I18n.tr("The current password is wrong.") I18n.tr("The new passwords don't match.") I18n.tr("The new password is empty.")
  function changePassword(current, next, done) {
    if (root._busy)
      return;
    root._busy = true;
    BackendManager.call("account.changePassword", {
      "current": String(current ?? ""),
      "new": String(next ?? "")
    }, (error, result) => {
      root._busy = false;
      if (error) {
        done({
          "ok": false,
          "reason": "failed",
          "message": SystemInfoManager.errorText(error)
        });
        return;
      }
      done({
        "ok": result.ok,
        "reason": result.reason ?? "",
        "message": I18n.tr(result.message ?? "")
      });
    });
  }

  // rpc: account.setIcon, account.setRealName
  function _change(method, params) {
    if (root._busy || Paths.greeter)
      return;
    root._busy = true;
    root._error = "";
    BackendManager.call(method, params, (error, result) => {
      root._busy = false;
      if (error) {
        root._error = SystemInfoManager.errorText(error);
        return;
      }
      root._show(result);
    });
  }

  function _show(account) {
    root._account = account;
    root._iconRevision++;
  }

  property var _account: ({})
  property int _iconRevision: 0
  property bool _busy: false
  property string _error: ""

  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      root.refresh();
    }
  }

  Component.onCompleted: {
    if (BackendManager.ready)
      root.refresh();
  }
}
