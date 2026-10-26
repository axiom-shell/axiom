pragma Singleton
import QtQuick

/**
 * Turns the config schema into the settings page's layout: categories
 * (`x-category` on each top-level section, ordered by the root's
 * `x-categories`), each made of
 * groups (the section's own fields, then one per nested object), each made
 * of form rows for SchemaField. Keys marked `x-settings: false` are
 * skipped (edited elsewhere: the bar editor, the Themes page, ...).
 * Depends on the schema only, so it's safe as a Repeater model.
 */
QtObject {
  id: root

  // Flattens an object schema into form rows:
  //   { kind: "group", title, path, showIf } for a nested object
  //   { kind: "field", title, path, schema }  for an editable value
  //   { kind: "array", title, path, schema }  for an array of objects
  // A nested object's `x-showIf` goes on its group row and, as
  // `groupShowIf` ([{ condition, path }], path: the object's parent), on
  // every row inside it
  function rows(objectSchema, path) {
    const result = [];
    for (const key in objectSchema.properties ?? {}) {
      const prop = objectSchema.properties[key];
      if (prop["x-settings"] === false)
        continue;
      const propPath = path.concat(key);
      if (prop.type === "object" && prop.properties) {
        const children = rows(prop, propPath);
        if (children.length > 0) {
          const showIf = prop["x-showIf"] ?? null;
          result.push({
            "kind": "group",
            "title": prop.title ?? key,
            "path": propPath,
            "showIf": showIf
          });
          if (showIf)
            children.forEach(child => child.groupShowIf = [
                {
                  "condition": showIf,
                  "path": path
                }
              ].concat(child.groupShowIf ?? []));
          result.push(...children);
        }
      } else if (prop.type === "array" && prop.items?.properties) {
        result.push({
          "kind": "array",
          "title": prop.title ?? key,
          "path": propPath,
          "schema": prop
        });
      } else if (["boolean", "integer", "string"].includes(prop.type) || (prop.type === "array" && prop.items?.type === "string")) {
        result.push({
          "kind": "field",
          "title": prop.title ?? key,
          "path": propPath,
          "schema": prop
        });
      }
    }
    return result;
  }

  // `x-showIf: { sibling: value | [values] | { not: value } | { notEmpty: true } }`: whether
  // it holds (every key), with valueOf(key) giving a sibling's value. A
  // plain key may be dotted (`open.onHover`: inside a sibling) and start
  // with `../` (the parent's sibling): keyPath resolves both. A key
  // starting with `/` is a dotted path from the config's root
  // ("/Workspaces.layout"), which valueOf resolves too (callers use
  // SettingsManager.configValueAt). `anyOf: [conditions]` holds when any
  // of them does.
  function showIfHolds(condition, valueOf) {
    if (!condition)
      return true;
    return Object.keys(condition).every(key => {
      const want = condition[key];
      if (key === "anyOf")
        return Array.prototype.some.call(want, any => root.showIfHolds(any, valueOf));
      const value = valueOf(key);
      // Passed in from another file, a schema array arrives as a list
      // object, not a JS Array
      if (want !== null && typeof want === "object" && typeof want.length === "number")
        return Array.prototype.includes.call(want, value);
      if (want !== null && typeof want === "object" && want.notEmpty)
        return (value?.length ?? 0) > 0;
      if (want !== null && typeof want === "object")
        return value !== want.not;
      return value === want;
    });
  }

  // Stored values per shown one for a number with `x-unit`: a duration
  // is stored in ms and shown in its unit (`s`, `min`, `h`, `d`); any
  // other unit shows the value as stored
  function unitScale(unit) {
    return ({
        "s": 1000,
        "min": 60000,
        "h": 3600000,
        "d": 86400000
      })[unit] ?? 1;
  }

  // `node` with every object `$ref` in its properties (Bars.style's
  // BarStyle) replaced by the definition, the keys beside the `$ref` over
  // it, down through nested objects (not array items)
  function _resolved(node, schema) {
    if (!node?.properties)
      return node;
    const properties = {};
    for (const key in node.properties) {
      let prop = node.properties[key];
      if (prop.$ref) {
        const definition = schema.definitions?.[prop.$ref.replace("#/definitions/", "")];
        if (definition) {
          prop = Object.assign({}, definition, prop);
          delete prop.$ref;
        }
      }
      properties[key] = root._resolved(prop, schema);
    }
    return Object.assign({}, node, {
      "properties": properties
    });
  }

  // The `default` of the property at `path` (keys) under `objectSchema`
  // (nested through `properties`), or undefined for none
  function defaultAt(objectSchema, path) {
    let schema = objectSchema;
    for (const key of path)
      schema = schema?.properties?.[key];
    return schema?.default;
  }

  // A plain condition key (`mode`, `open.onHover`, `../position`) as a
  // path, from `parent`: the path of the object holding the condition
  function keyPath(parent, key) {
    let base = parent;
    let rest = key;
    while (rest.startsWith("../")) {
      base = base.slice(0, -1);
      rest = rest.slice(3);
    }
    return base.concat(rest.split("."));
  }

  // The first key of `condition` (as showIfHolds reads it) that doesn't
  // hold, or "" when it all does: why an `x-enabledIf` setting is greyed
  // out
  function failingKey(condition, valueOf) {
    if (!condition)
      return "";
    return Object.keys(condition).find(key => {
      const one = {};
      one[key] = condition[key];
      return !root.showIfHolds(one, valueOf);
    }) ?? "";
  }

  // Whether the setting at `path` (from the schema's root) can be set at
  // all under the running compositor: the `/$` keys (SettingsManager.
  // configValueAt) of the `x-showIf` and `x-enabledIf` of its section, the
  // objects it's in and its own hold. Other keys depend on the config, and
  // are left out.
  function compositorAllows(schema, path, valueOf) {
    let node = schema;
    for (const key of path) {
      node = node?.properties?.[key];
      if (!node)
        return false;
      const condition = Object.assign({}, node["x-showIf"] ?? {}, node["x-enabledIf"] ?? {});
      const own = Object.keys(condition).filter(name => name.startsWith("/$")).reduce((result, name) => {
        result[name] = condition[name];
        return result;
      }, {});
      if (!root.showIfHolds(own, valueOf))
        return false;
    }
    return true;
  }

  // An object definition's fields as titled groups, for an editor that
  // lays one object out itself (the bar and edge menu panels): by
  // `x-group` in `x-order` order, fields without a group last under
  // "Other", `exclude` (keys edited elsewhere, dotted into a nested
  // object: "layout.modules") and `x-settings: false` keys left out. A
  // nested object's fields go to their own groups (else its, else its
  // parent's): a group's `schema` holds the object with just those fields,
  // for SchemaPropertiesForm.
  // [{ title, keys, schema: { key: fieldSchema } }]
  function objectGroups(definition, exclude) {
    const named = [];
    const other = {
      "title": "Other",
      "keys": [],
      "schema": {}
    };
    const ordered = node => {
      const order = node["x-order"] ?? [];
      const rank = key => {
        const index = order.indexOf(key);
        return index < 0 ? order.length : index;
      };
      return Object.keys(node.properties ?? {}).sort((a, b) => rank(a) - rank(b));
    };
    // Puts `prop` at `path` (from the definition) into its group
    function place(prop, path, inherited) {
      if ((exclude ?? []).includes(path.join(".")) || prop["x-settings"] === false)
        return;
      const title = prop["x-group"] ?? inherited;
      if (prop.type === "object" && prop.properties) {
        for (const key of ordered(prop))
          place(prop.properties[key], path.concat(key), title);
        return;
      }
      let group = title ? named.find(g => g.title === title) : other;
      if (!group) {
        group = {
          "title": title,
          "keys": [],
          "schema": {}
        };
        named.push(group);
      }
      if (!group.keys.includes(path[0]))
        group.keys.push(path[0]);
      if (path.length === 1) {
        group.schema[path[0]] = prop;
        return;
      }
      // The nested object down to `prop`, holding this group's fields only
      let node = group.schema;
      let source = definition;
      for (const key of path.slice(0, -1)) {
        source = source.properties[key];
        node[key] = node[key] ?? Object.assign({}, source, {
          "properties": {}
        });
        node = node[key].properties;
      }
      node[path[path.length - 1]] = prop;
    }
    for (const key of ordered(definition))
      place(definition.properties[key], [key], undefined);
    return other.keys.length > 0 ? named.concat([other]) : named;
  }

  // One section as cards: { kind, key, title, description, section, path,
  // rows, showIf, showIfParent, wide }. The section's direct values make the
  // first card (titled by the section), each nested object the next ones.
  // Fields with `x-group` go on a card of that name instead, so one object
  // can make several cards; a nested object with `x-group` joins that card
  // (under its own title), its `x-showIf` on its rows. A nested object's
  // `x-showIf` (on its siblings) otherwise applies to all its cards. A
  // section's `x-card: { file, title, wide, folds, perField }` names a
  // hand-built card (settings/<file>Card.qml, titled `title`) that goes
  // first (`folds`: it folds like the generated cards, given its
  // `foldKey`; `wide`: it spans both columns); its `x-intro` names a
  // hand-built piece (settings/<name>.qml) at the top of the section's own
  // card, above its fields (`intro`), as a nested object's does on its
  // own. `perField` makes each of the section's direct fields a card of
  // its own, titled and described by the field and sorted by title, a
  // switch's row labelled "Enabled"; the section's description gets a card
  // first. A card holding a field marked `x-wide` spans both columns
  // (`wide`).
  function groups(schema, sectionKey) {
    const section = root._resolved(schema.properties[sectionKey], schema);
    const sectionTitle = section.title ?? sectionKey;
    const handBuilt = section["x-card"] ?? {};
    const perField = handBuilt.perField === true;
    const result = [];
    if (handBuilt.file)
      result.push({
        "kind": "card",
        "key": sectionKey + ":" + handBuilt.file,
        "card": handBuilt.file,
        "folds": handBuilt.folds === true,
        "wide": handBuilt.wide === true,
        "title": handBuilt.title ?? sectionTitle,
        "description": "",
        "section": sectionTitle,
        "path": [sectionKey],
        "rows": [],
        "showIf": null,
        "showIfParent": []
      });

    // Cards by title, in order of first appearance
    const cards = [];
    function cardFor(title, base) {
      let card = cards.find(c => c.title === title && c.path.join(".") === base.path.join("."));
      if (!card) {
        card = Object.assign({
          "kind": "rows",
          "title": title,
          "rows": [],
          "intro": ""
        }, base);
        card.key = base.path.join(".") + (title === base.defaultTitle ? "" : ":" + title);
        cards.push(card);
      }
      return card;
    }

    // `order` (the object's `x-order`) puts keys first: the schema reaches
    // QML as a map, whose keys come out sorted, and a card's place is its
    // first field's
    function place(objectSchema, path, base, order) {
      const rank = key => {
        const index = (order ?? []).indexOf(key);
        return index < 0 ? Infinity : index;
      };
      const keys = Object.keys(objectSchema.properties ?? {}).sort((a, b) => rank(a) - rank(b));
      for (const key of keys) {
        const prop = objectSchema.properties[key];
        if (prop["x-settings"] === false)
          continue;
        const fieldRows = root.rows({
          "properties": {
            [key]: prop
          }
        }, path);
        if (fieldRows.length === 0)
          continue;
        if (perField && path.length === 1) {
          const title = prop.title ?? key;
          const card = cardFor(title, base);
          card.description = prop.description ?? "";
          // A switch's own title would repeat the card's: I18n.tr("Enabled")
          card.rows.push(...fieldRows.map(row => Object.assign(row, prop.type === "boolean" ? {
              "label": "Enabled",
              "description": ""
            } : {
              "description": ""
            })));
        } else {
          cardFor(prop["x-group"] ?? base.defaultTitle, base).rows.push(...fieldRows);
        }
      }
    }

    if (perField && section.description)
      cardFor(sectionTitle, {
        "defaultTitle": sectionTitle,
        "description": section.description,
        "section": sectionTitle,
        "path": [sectionKey],
        "showIf": null,
        "showIfParent": []
      });

    // Direct values first, then each nested object
    const direct = {};
    const nested = [];
    for (const key in section.properties ?? {}) {
      const prop = section.properties[key];
      if (prop.type === "object" && prop.properties)
        nested.push(key);
      else
        direct[key] = prop;
    }
    place({
      "properties": direct
    }, [sectionKey], {
      "defaultTitle": sectionTitle,
      "description": section.description ?? "",
      "section": sectionTitle,
      "path": [sectionKey],
      "showIf": null,
      "showIfParent": []
    }, section["x-order"]);
    for (const key of nested) {
      const prop = section.properties[key];
      if (prop["x-settings"] === false)
        continue;
      if (prop["x-group"]) {
        const objectRows = root.rows({
          "properties": {
            [key]: prop
          }
        }, [sectionKey]);
        // A heading repeating the card's title is left out (its rows keep
        // the object's `x-showIf`)
        if (objectRows[0]?.title === prop["x-group"])
          objectRows.shift();
        cardFor(prop["x-group"], {
          "defaultTitle": sectionTitle,
          "description": section.description ?? "",
          "section": sectionTitle,
          "path": [sectionKey],
          "showIf": null,
          "showIfParent": []
        }).rows.push(...objectRows);
        continue;
      }
      place(prop, [sectionKey, key], {
        "defaultTitle": prop.title ?? key,
        "description": prop.description ?? "",
        "section": sectionTitle,
        "path": [sectionKey, key],
        "showIf": prop["x-showIf"] ?? null,
        "showIfParent": [sectionKey]
      }, prop["x-order"]);
    }
    // A description belongs to the object's first card only (each of
    // `perField`'s cards has its field's)
    const seen = new Set();
    for (const card of cards) {
      const path = card.path.join(".");
      if (seen.has(path) && !(perField && card.path.length === 1))
        card.description = "";
      seen.add(path);
      delete card.defaultTitle;
      card.wide = card.rows.some(row => row.schema?.["x-wide"] === true);
    }
    // The section's card, then its fields' by title, then nested objects'
    if (perField) {
      const isOwn = card => card.path.length === 1 && card.title !== sectionTitle;
      const fields = cards.filter(isOwn).sort((a, b) => a.title.localeCompare(b.title));
      const intro = cards.filter(card => card.path.length === 1 && card.title === sectionTitle);
      const nestedCards = cards.filter(card => card.path.length > 1);
      cards.splice(0, cards.length, ...intro, ...fields, ...nestedCards);
    }
    const own = cards.find(card => card.path.length === 1 && card.title === sectionTitle);
    if (own && section["x-intro"])
      own.intro = section["x-intro"];
    for (const key of nested) {
      const prop = section.properties[key];
      const card = prop["x-intro"] ? cards.find(card => card.path.join(".") === sectionKey + "." + key && card.title === (prop.title ?? key)) : null;
      if (card)
        card.intro = prop["x-intro"];
    }
    return result.concat(cards);
  }

  // A category's cards in page order: its sections' (`groups`), then its
  // own `card`. Wide cards ahead of every narrow one stay at the top; any
  // other goes to the bottom, so none cuts the columns partway down
  // (`methods/ColumnSplit` lays them out)
  function categoryGroups(schema, category) {
    const all = [].concat(...(category?.sections ?? []).map(section => root.groups(schema, section)));
    if (category?.card)
      all.push({
        "kind": "card",
        "key": category.name + ":" + category.card,
        "card": category.card,
        "folds": false,
        "wide": true,
        "title": category.cardTitle || category.name,
        "description": "",
        "section": category.name,
        "path": [],
        "rows": [],
        "showIf": null,
        "showIfParent": []
      });
    const lead = all.findIndex(group => !group.wide);
    if (lead < 0)
      return all;
    const rest = all.slice(lead);
    return all.slice(0, lead).concat(rest.filter(group => !group.wide), rest.filter(group => group.wide));
  }

  // Where the settings page shows a setting (a key path, as an array or
  // dotted: "Appearance.font.size"), or a section or object ("BarStyle",
  // "Appearance.shape"): { category, key, title, row } for the first card
  // holding it in page order (`key` its group key, `title` the setting's
  // or card's, `row` the exact row's path, or null for a section or
  // object), or null when no card shows it. `valueOf` as `categories`
  function locate(schema, path, valueOf) {
    const target = Array.isArray(path) ? path : String(path).split(".");
    const within = p => target.length <= p.length && target.every((key, i) => p[i] === key);
    for (const category of root.categories(schema, valueOf)) {
      for (const group of root.categoryGroups(schema, category)) {
        const row = group.rows.find(row => within(row.path));
        if (!row && !(group.path.length > 0 && within(group.path)))
          continue;
        const exact = row && row.path.length === target.length ? row : null;
        return {
          "category": category.name,
          "key": group.key,
          "title": exact ? exact.title : group.title,
          "row": exact ? exact.path : null
        };
      }
    }
    return null;
  }

  // [{ name, icon, card, cardTitle, sections: [key], links: [page type] }]:
  // the root's `x-categories` in order (`icon`, and `card`, a hand-built
  // card of the category's own: settings/<card>Card.qml, wide, titled
  // `cardTitle` in the sidebar), then any other `x-category` in schema
  // order. A section without `x-category` is a category of its own. A
  // declared category with no sections and no card is left out, as is a
  // section whose own `x-showIf` (`/`-rooted keys, read by `valueOf`; e.g. the
  // compositor's, as SettingsManager.configValueAt reads them) fails.
  function categories(schema, valueOf) {
    const make = (name, declared) => ({
          "name": name,
          "icon": declared?.icon ?? "settings",
          "card": declared?.card ?? "",
          "cardTitle": declared?.cardTitle ?? "",
          "sections": [],
          "links": []
        });
    const result = (schema?.["x-categories"] ?? []).map(declared => make(declared.name, declared));
    for (const key in schema?.properties ?? {}) {
      const section = schema.properties[key];
      if (section.type !== "object" || section["x-settings"] === false || groups(schema, key).length === 0)
        continue;
      if (valueOf && !showIfHolds(section["x-showIf"], valueOf))
        continue;
      const name = section["x-category"] ?? section.title ?? key;
      let category = result.find(c => c.name === name);
      if (!category) {
        category = make(name, null);
        result.push(category);
      }
      category.sections.push(key);
      for (const link of section["x-links"] ?? [])
        if (!category.links.includes(link))
          category.links.push(link);
    }
    return result.filter(c => c.sections.length > 0 || c.card !== "");
  }
}
