pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Lock keys' state for the OSD: each LED, and whether they're read at all
// (`available`). Holds LockKeysManager, so the LEDs are polled the whole
// session while an OSD lists them, as with the LockKeys widget; one
// reading sets several keys at once, judged once it's all in (the base's
// Qt.callLater)
OSDWatch {
  holds: [LockKeysManager]

  state: ({
      "capsLock": {
        "available": LockKeysManager.available,
        "value": LockKeysManager.capsLock
      },
      "numLock": {
        "available": LockKeysManager.available,
        "value": LockKeysManager.numLock
      },
      "scrollLock": {
        "available": LockKeysManager.available,
        "value": LockKeysManager.scrollLock
      }
    })
}
