pragma Singleton
import QtQuick
import qs.config

// Small JSON state files in Paths.statePath: createStateHandler(name)
// gives a shared save/load handler per name. Written through axiom
// (FileManager.write), which makes the folder, 0700 (the clipboard pins
// are kept here).
QtObject {
  id: root

  readonly property string stateDir: Paths.statePath

  /**
     * @brief Creates a state handler for a specific service
     * @param serviceName The name of the service (e.g., "launcher")
     * @returns An object with save/load methods, shared by every caller
     *   asking for the same name
     */
  function createStateHandler(serviceName) {
    if (_handlers[serviceName])
      return _handlers[serviceName];
    const filepath = stateDir + serviceName + ".json";
    const handler = {
      save: function (data) {
        try {
          FileManager.write(filepath, JSON.stringify(data, null, 2));
          console.log(`[StateManager] ${serviceName} state saved.`);
          return true;
        } catch (e) {
          console.error(`[StateManager] Failed to save ${serviceName}:`, e);
          return false;
        }
      },
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
    _handlers[serviceName] = handler;
    return handler;
  }

  property var _handlers: ({})
}
