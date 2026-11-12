pragma Singleton
import QtQuick

// The fields of the config schema that refer to something defined elsewhere
// (`x-ref`, schema-annotations.md): where they are, read from the built
// schema. No file access, processes or services.
QtObject {
  id: root

  // The fields of kind `kind` in `schema` (the built config schema):
  // [{ path, key, when, usedBy, name, nameLabels }], `path` the keys from the config's
  // root to the list of items (["Keybinds", "binds"]), `key` the field of
  // each item, the rest the `x-ref`'s. Found in the lists directly under a
  // section or a nested object (not in lists inside lists, so Keybinds'
  // saved presets aren't sites), in schema order.
  function sites(schema, kind) {
    const out = [];
    const resolve = node => {
      const ref = node?.$ref;
      if (!ref)
        return node;
      const base = schema?.definitions?.[ref.replace("#/definitions/", "")];
      return base ? Object.assign({}, base, node) : node;
    };
    const walk = (node, path) => {
      const properties = resolve(node)?.properties ?? {};
      Object.keys(properties).forEach(key => {
        const prop = resolve(properties[key]);
        if (prop?.type === "array") {
          const fields = resolve(prop.items)?.properties ?? {};
          Object.keys(fields).forEach(field => {
            const ref = fields[field]?.["x-ref"];
            if (ref?.kind === kind)
              out.push({
                "path": path.concat([key]),
                "key": field,
                "when": ref.when ?? ({}),
                "usedBy": ref.usedBy ?? "",
                "name": ref.name ?? "",
                "nameLabels": fields[ref.name]?.["x-enumLabels"] ?? ({})
              });
          });
        } else if (prop?.properties) {
          walk(prop, path.concat([key]));
        }
      });
    };
    walk(schema, []);
    return out;
  }
}
