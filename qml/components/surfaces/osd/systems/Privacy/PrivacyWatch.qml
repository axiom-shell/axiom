pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Camera, microphone and screen in use's state for the OSD: the streams
// capturing each, by node id (an app's name read after its stream starts
// isn't another app: the id stays put), with their app's name
OSDWatch {
  id: root

  function _members(nodes) {
    return nodes.map(n => ({
          "id": n.id,
          "app": AudioManager.appName(n)
        }));
  }

  state: ({
      "camera": {
        "members": root._members(PrivacyManager.cameraCaptures)
      },
      "micUse": {
        "members": root._members(AudioManager.micCaptures)
      },
      "screenShare": {
        "members": root._members(PrivacyManager.screenCaptures)
      }
    })
}
