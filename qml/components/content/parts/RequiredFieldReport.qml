pragma ComponentBehavior: Bound
import QtQuick

import qs.services.ui

// Tells the greeter or lock surface its required field's module (Login,
// Password) shows, so the surface doesn't draw its own: reported under
// `key`, the host's key while on that surface, else "".
QtObject {
  id: root

  property string key: ""
  property string _reportedKey: ""

  function _report() {
    if (root.key === root._reportedKey)
      return;
    SurfaceManager.reportRequiredField(root._reportedKey, false);
    SurfaceManager.reportRequiredField(root.key, true);
    root._reportedKey = root.key;
  }

  onKeyChanged: root._report()
  Component.onCompleted: root._report()
  Component.onDestruction: SurfaceManager.reportRequiredField(root._reportedKey, false)
}
