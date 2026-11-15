pragma Singleton
import QtQuick

// The fields of the config schema that refer to something defined elsewhere
// (`x-ref`, schema-annotations.md): where they are, read from the built
// schema. No file access, processes or services.
QtObject {
  id: root

  // The fields of kind `kind` in `schema` (the built config schema):
  // [{ path, field, many, key, when, usedBy, name, nameLabels }], `path` the
  // keys from the config's root to the list of items (["Keybinds", "binds"]),
  // `field` the keys from an item to the field (["window", "special", "id"]:
  // nested objects are walked, arrays of objects aren't), `many` whether the
  // field is an array of ids (the `x-ref` on the array), `key` the field's keys
  // joined by ".", the rest the `x-ref`'s (`name` is a key of the item itself,
  // `when` is over the keys of the field's own object). Found in the lists
  // directly under a section or a nested object (not in lists inside lists, so
  // Keybinds' saved presets aren't sites), in schema order.
  function sites(schema, kind) {
    const out = [];
    const resolve = node => {
      const ref = node?.$ref;
      if (!ref)
        return node;
      const base = schema?.definitions?.[ref.replace("#/definitions/", "")];
      return base ? Object.assign({}, base, node) : node;
    };
    const fieldsOf = (node, item, path, prefix) => {
      const properties = resolve(node)?.properties ?? {};
      Object.keys(properties).forEach(name => {
        const prop = resolve(properties[name]);
        const ref = prop?.["x-ref"];
        const field = prefix.concat([name]);
        if (ref?.kind === kind)
          out.push({
            "path": path,
            "field": field,
            "many": prop.type === "array",
            "key": field.join("."),
            "when": ref.when ?? ({}),
            "usedBy": ref.usedBy ?? "",
            "name": ref.name ?? "",
            "nameLabels": resolve(item)?.properties?.[ref.name]?.["x-enumLabels"] ?? ({})
          });
        else if (prop?.type === "object" && prop.properties)
          fieldsOf(prop, item, path, field);
      });
    };
    const walk = (node, path) => {
      const properties = resolve(node)?.properties ?? {};
      Object.keys(properties).forEach(key => {
        const prop = resolve(properties[key]);
        if (prop?.type === "array")
          fieldsOf(prop.items, resolve(prop.items), path.concat([key]), []);
        else if (prop?.properties)
          walk(prop, path.concat([key]));
      });
    };
    walk(schema, []);
    return out;
  }

  // The ids the config refers to, from `sites`: [{ id, usedBy, name,
  // translate }] for each id held by each item of `config` whose field's
  // object `when` matches: a string field's non-empty value, or each non-empty
  // string of an array field. `usedBy` is the source text of the reason,
  // `name` what it names (the item's `name` key, an empty one falling back to
  // its `id`, or the field's `x-enumLabels` entry, `translate` then true, as
  // source text).
  function references(config, sites) {
    const out = [];
    (sites ?? []).forEach(site => {
      let items = config;
      for (const key of site.path)
        items = items?.[key];
      if (!Array.isArray(items))
        return;
      items.forEach(item => {
        let parent = item;
        for (const key of site.field.slice(0, -1))
          parent = parent?.[key];
        const value = parent?.[site.field[site.field.length - 1]];
        if (!SchemaLayout.showIfHolds(site.when, key => parent?.[key]))
          return;
        const raw = String(item?.[site.name] ?? "") || String(item?.id ?? "");
        const label = site.nameLabels?.[raw];
        (site.many ? (Array.isArray(value) ? value : []) : [value]).forEach(id => {
          if (typeof id !== "string" || id === "")
            return;
          out.push({
            "id": id,
            "usedBy": site.usedBy,
            "name": label ?? raw,
            "translate": label !== undefined
          });
        });
      });
    });
    return out;
  }
}
