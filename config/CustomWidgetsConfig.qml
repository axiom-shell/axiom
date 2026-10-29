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

  // A library key as what it adds: the bar widget and module libraries
  // offer each custom widget as "CustomWidget:<id>", which adds a
  // CustomWidget with its definition; any other key is a type as is.
  // { type, properties (null for a plain type) }
  function splitKey(key) {
    const custom = /^CustomWidget:(.+)$/.exec(key ?? "");
    return custom ? {
      "type": "CustomWidget",
      "properties": {
        "definition": custom[1]
      }
    } : {
      "type": key,
      "properties": null
    };
  }

  // The library entries for the custom widgets, built over `base` (the
  // CustomWidget type's own entry, null: none): its info with each
  // definition's key, name, icon and the Custom group
  function libraryEntries(base) {
    if (!base)
      return [];
    return root.items.map(def => Object.assign({}, base, {
        "type": "CustomWidget:" + def.id,
        "label": def.name || def.id,
        "icon": def.icon || base.icon,
        "group": "Custom",
        "definition": def.id
      }));
  }
}
