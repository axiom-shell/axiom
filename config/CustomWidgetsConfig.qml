pragma Singleton
import QtQuick
import qs.services.core

// Reader for the CustomWidgets section: the custom JSON widgets
// (CustomWidget definitions: a script, its fields, its bar style and its
// module), edited on the Custom widgets page and drawn by the CustomWidget
// bar widget and module (CustomWidgetsManager runs them)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.CustomWidgets

  // Goes through a string so a config change leaving them unchanged doesn't
  // notify their readers
  readonly property string _itemsJson: JSON.stringify(_c.items)
  readonly property var items: JSON.parse(_itemsJson)

  // id -> definition
  readonly property var byId: items.reduce((map, item) => {
    map[item.id] = item;
    return map;
  }, {})

  // A definition by id, or null
  function definition(id) {
    return root.byId[id] ?? null;
  }
}
