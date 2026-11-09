pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

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

  // The element kinds a module is built from (the CustomElement oneOf:
  // components/content/parts/custom/elements/<Type>/schema.yaml), by
  // label: { type, label, icon, size ([w, h] sub-cells it's added at,
  // `x-defaultSize`), slots (its bindings, `x-slots`), actions (the
  // commands it runs, `x-actions`), actionsSchema (theirs, a properties
  // schema), options (its look, a properties schema), optionsOrder }. Labels and titles are English: the editor
  // translates them
  readonly property var elementKinds: {
    const schema = ConfigManager.configSchema;
    return (schema?.definitions?.CustomElement?.oneOf ?? []).map(option => {
      const def = schema.definitions[option.$ref.replace("#/definitions/", "")];
      return {
        "type": def.properties.type.const,
        "label": def.properties.type.description,
        "icon": def["x-icon"] ?? "widgets",
        "size": def["x-defaultSize"] ?? [4, 4],
        "slots": def["x-slots"] ?? [],
        "actions": def["x-actions"] ?? [],
        "actionsSchema": Utils.pick(def.properties.actions.properties, def["x-actions"] ?? []),
        "options": def.properties.options?.properties ?? ({}),
        "optionsOrder": def.properties.options?.["x-order"] ?? []
      };
    }).sort((a, b) => a.label.localeCompare(b.label));
  }

  // An element kind (elementKinds), or null
  function elementKind(type) {
    return root.elementKinds.find(k => k.type === type) ?? null;
  }

  // A new element of `type` at `place`, at its schema defaults
  function newElement(type, id, place) {
    return ConfigManager.withDefaults({
      "id": id,
      "type": type,
      "place": place
    }, "CustomElement");
  }

  // The elements drawn for a definition without any, and what "Start
  // from the default layout" copies (CustomWidgetData.defaultElements), at
  // their schema defaults
  function defaultElements(size, hasValue) {
    return CustomWidgetData.defaultElements(size, hasValue).map(e => ConfigManager.withDefaults(e, "CustomElement"));
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
