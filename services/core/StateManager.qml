pragma Singleton
import QtQuick
import Quickshell.Io
import qs.config

// Small JSON state files in Paths.statePath: createStateHandler(name)
// gives a shared save/load handler per name.
QtObject {
  id: root

  readonly property string stateDir: Paths.statePath

  /**
     * @brief Creates a state handler for a specific service
     * @param serviceName The name of the service (e.g., "launcher")
     * @returns An object with save/load methods, shared by every caller
     *   asking for the same name (so re-created consumers don't each leak
     *   a FileView)
     */
  function createStateHandler(serviceName) {
    if (_handlers[serviceName])
      return _handlers[serviceName];
    const stateFile = serviceName + ".json";
    const fileView = fileViewComponent.createObject(root, {
      path: Qt.resolvedUrl(stateDir + stateFile)
    });

    const handler = {
      save: function (data) {
        try {
          const stateString = JSON.stringify(data, null, 2);
          fileView.setText(stateString);
          console.log(`[StateManager] ${serviceName} state saved.`);
          return true;
        } catch (e) {
          console.error(`[StateManager] Failed to save ${serviceName}:`, e);
          return false;
        }
      },
      load: function (defaultValue) {
        const filepath = stateDir + stateFile;
        console.log(`[StateManager] Loading ${serviceName} from`, filepath);
        const content = FileManager.read(Qt.resolvedUrl(filepath));

        if (content) {
          try {
            const state = JSON.parse(content);
            console.log(`[StateManager] ${serviceName} loaded successfully.`);
            return state;
          } catch (e) {
            console.error(`[StateManager] Failed to parse ${serviceName}:`, e);
            return defaultValue;
          }
        } else {
          console.log(`[StateManager] No ${serviceName} state found.`);
          return defaultValue;
        }
      }
    };
    _handlers[serviceName] = handler;
    return handler;
  }

  property var _handlers: ({})

  // FileView doesn't create folders, so this one is made first, 0700 (the
  // clipboard pins are kept here). chmod too: mkdir -m leaves a folder that
  // already exists alone, whatever its mode.
  property Process _makeDir: Process {
    running: true
    command: ["sh", "-c", 'mkdir -p "$1" && chmod 700 "$1"', "sh", root.stateDir]
  }

  property Component _fileViewComponent: Component {
    id: fileViewComponent
    FileView {
      // A missing state file is normal (nothing saved yet): load() falls
      // back to its default
      printErrors: false
      blockWrites: true
      atomicWrites: true
      onSaveFailed: error => {
        console.error("[StateManager] Save failed:", FileViewError.toString(error));
      }
    }
  }
}
