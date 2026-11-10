pragma Singleton
import QtQuick
import qs.config

// Small JSON state files in Paths.statePath: createStateHandler(name)
// gives a shared save/load handler per name. Written through axiom
// (FileManager.write), which makes the folder, 0700 (the clipboard pins
// are kept here). createSessionHandler(name) is the same for state that
// lasts the login session alone, in Paths.runtimePath (on
// $XDG_RUNTIME_DIR, gone at logout): it survives qs reloads and restarts.
QtObject {
  id: root

  /**
     * @brief Creates a state handler for a specific service
     * @param serviceName The name of the service (e.g., "launcher")
     * @returns An object with save/load methods, shared by every caller
     *   asking for the same name
     */
  function createStateHandler(serviceName) {
    return root._handler(serviceName, Paths.statePath);
  }

  // The same, kept for the login session alone (Paths.runtimePath +
  // "state/")
  function createSessionHandler(serviceName) {
    return root._handler(serviceName, Paths.runtimePath + "state/");
  }

  function _handler(serviceName, dir) {
    const filepath = dir + serviceName + ".json";
    if (_handlers[filepath])
      return _handlers[filepath];
    const handler = {
      save: data => FileManager.write(filepath, JSON.stringify(data, null, 2)),
      load: function (defaultValue) {
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
    _handlers[filepath] = handler;
    return handler;
  }

  property var _handlers: ({})
}
