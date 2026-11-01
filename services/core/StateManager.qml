pragma Singleton
import QtQuick
import qs.config

// Small JSON state files in Paths.statePath: createStateHandler(name)
// gives a shared save/load handler per name. Written through axiom
// (FileManager.write), which makes the folder, 0700 (the clipboard pins
// are kept here).
QtObject {
  id: root

  /**
     * @brief Creates a state handler for a specific service
     * @param serviceName The name of the service (e.g., "launcher")
     * @returns An object with save/load methods, shared by every caller
     *   asking for the same name
     */
  function createStateHandler(serviceName) {
    if (_handlers[serviceName])
      return _handlers[serviceName];
    const filepath = Paths.statePath + serviceName + ".json";
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
    _handlers[serviceName] = handler;
    return handler;
  }

  property var _handlers: ({})
}
