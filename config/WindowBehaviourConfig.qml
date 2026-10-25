pragma Singleton
import QtQuick
import qs.services.core

// Reader for the WindowBehaviour section: focus and the cursor, which
// every compositor's managed config writes (each field by its
// x-compositor annotation). Named WindowBehaviourConfig as the section is read
// whole.
QtObject {
  readonly property var _c: ConfigManager.config.WindowBehaviour

  // Goes through a string so a reload that leaves it unchanged doesn't
  // write it again
  readonly property string _behaviourJson: JSON.stringify(_c)
  readonly property var behaviour: JSON.parse(_behaviourJson)
}
