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

  // The keys of its object a field draws itself, so their own rows hide:
  // its `x-rowDraws`, and an icon field's `x-iconText` siblings
  function drawnKeys(fieldSchema) {
    const keys = Array.isArray(fieldSchema?.["x-rowDraws"]) ? fieldSchema["x-rowDraws"].slice() : [];
    return keys.concat(root.iconTextKeys(fieldSchema));
  }

  // The sibling keys an icon field's `x-iconText` ({ mode, text }) draws
  // in its row: its mode's, then its text's, each where given
  function iconTextKeys(fieldSchema) {
    const iconText = fieldSchema?.["x-iconText"];
    return [iconText?.mode, iconText?.text].filter(key => typeof key === "string" && key !== "");
  }

  // Flattens an object schema into form rows:
  //   { kind: "group", title, path, showIf } for a nested object
  //   { kind: "object", title, path, schema } for a nested object with
  //     `x-row`, drawn whole by that row
  //   { kind: "field", title, path, schema }  for an editable value
  //   { kind: "array", title, path, schema }  for an array of objects
  // A nested object's `x-showIf` goes on its group row and, as
  // `groupShowIf` ([{ condition, path }], path: the object's parent), on
  // every row inside it. A nested object marked `x-fold` folds its rows
  // behind its title: its group row has `fold: true`, and each row inside
  // it `foldedBy`, the dotted path of the innermost such object. A row
  // another field draws (drawnKeys) has `drawnBy`, that field's dotted
  // path; every row under an `x-row` object has `drawnBy` its path (and
  // no `foldedBy`: its folds aren't drawn). Keys go in
  // their object's `x-order` first (the schema reaches QML as a map)
  function rows(objectSchema, path) {
    const result = [];
    const order = objectSchema["x-order"] ?? [];
    const keys = Object.keys(objectSchema.properties ?? {});
    // (Ties keep their place: the engine's sort isn't stable)
    const rank = key => {
      const index = order.indexOf(key);
      return index < 0 ? order.length + keys.indexOf(key) : index;
    };
    for (const key of keys.slice().sort((a, b) => rank(a) - rank(b))) {
      const prop = objectSchema.properties[key];
      if (prop["x-settings"] === false)
        continue;
      const propPath = path.concat(key);
      if (prop.type === "object" && prop.properties && prop["x-row"]) {
        // One row draws it all (Bars.style's BarStyleBlock): its own row,
        // then every row under it, there for search, the changed list,
        // Discard and jumps, which take them as that row
        const showIf = prop["x-showIf"] ?? null;
        const children = rows(prop, propPath);
        for (const child of children) {
          child.drawnBy = propPath.join(".");
          delete child.foldedBy;
          if (showIf)
            child.groupShowIf = [
              {
                "condition": showIf,
                "path": path
              }
            ].concat(child.groupShowIf ?? []);
        }
        result.push({
          "kind": "object",
          "title": prop.title ?? key,
          "path": propPath,
          "schema": prop
        });
        result.push(...children);
      } else if (prop.type === "object" && prop.properties) {
        const children = rows(prop, propPath);
        if (children.length > 0) {
          const showIf = prop["x-showIf"] ?? null;
          const fold = prop["x-fold"] === true;
          result.push({
            "kind": "group",
            "title": prop.title ?? key,
            "path": propPath,
            "showIf": showIf,
            "fold": fold
          });
          if (fold)
            children.forEach(child => child.foldedBy = child.foldedBy ?? propPath.join("."));
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
      } else if (["boolean", "integer", "number", "string"].includes(prop.type) || (prop.type === "array" && prop.items?.type === "string")) {
        result.push({
          "kind": "field",
          "title": prop.title ?? key,
          "path": propPath,
          "schema": prop
        });
      }
    }
    // A field that also draws other keys of its object (drawnKeys: an
    // `x-row`'s `x-rowDraws`, dotted paths under it, or an icon field's
    // `x-iconText`) marks their rows `drawnBy` its dotted path: on the
    // settings page they're drawn inside it
    for (const row of result.filter(r => r.kind !== "group" && root.drawnKeys(r.schema).length > 0)) {
      const drawn = root.drawnKeys(row.schema).map(key => path.concat(key.split(".")).join("."));
      result.filter(r => r.kind !== "group" && drawn.includes(r.path.join("."))).forEach(r => r.drawnBy = row.path.join("."));
    }
    return result;
  }

  // What the field refers to (`x-ref`'s `kind`, "specialWorkspace"), or "" when
  // it refers to nothing or its `when` doesn't hold for the item (valueOf
  // gives the item's keys, as showIfHolds')
  function refKind(fieldSchema, valueOf) {
    const ref = fieldSchema?.["x-ref"];
    if (!ref || !root.showIfHolds(ref.when, valueOf))
      return "";
    return ref.kind ?? "";
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
      if (want !== null && typeof want === "object" && "includes" in want)
        // (a list object from another file, as `want` above)
        return value !== null && typeof value === "object" && typeof value.length === "number" && Array.prototype.includes.call(value, want.includes);
      if (want !== null && typeof want === "object")
        return value !== want.not;
      return value === want;
    });
  }

  // An enum field's options as tiles (`x-control: tiles`): [{ value,
  // hint }], every option (none hidden, unlike a dropdown's), `hint` null
  // while it applies, else why not: its `x-enumShowIf` condition fails
  // (valueOf as showIfHolds), the chosen one too. The hint is English, from
  // the field's `x-tileHint` (tileHint), "" for none: the form says it
  // generically and translates it
  function tileOptions(fieldSchema, options, valueOf) {
    const conditions = fieldSchema?.["x-enumShowIf"] ?? {};
    return Array.prototype.map.call(options ?? [], value => ({
          "value": value,
          "hint": root.showIfHolds(conditions[value], valueOf) ? null : root.tileHint(fieldSchema, value)
        }));
  }

  // `x-tileHint`: why an option (`value`) of a field doesn't apply, from
  // its map ({ value: reason }); with no `value`, why the whole field
  // doesn't (its `x-showIf` failing in a form that keeps its place), from
  // a string, or the map's "*" beside its options'. English, "" for none
  function tileHint(fieldSchema, value) {
    const hint = fieldSchema?.["x-tileHint"];
    const map = hint !== null && typeof hint === "object" ? hint : {};
    if (value === undefined)
      return typeof hint === "string" ? hint : typeof map["*"] === "string" ? map["*"] : "";
    return typeof map[value] === "string" ? map[value] : "";
  }

  // `keys` (an object's, in order) with each one marked `x-placeUnder:
  // <sibling>` (`properties`: the object's) moved directly under that
  // sibling's row: after it, the rows beside it (`x-beside`) and those
  // placed under it before. One naming a key not in `keys`, or one placed
  // itself, stays where it is
  function placedUnder(keys, properties) {
    const under = key => {
      const target = properties?.[key]?.["x-placeUnder"];
      return typeof target === "string" && target !== key && keys.includes(target) && typeof properties[target]?.["x-placeUnder"] !== "string" ? target : null;
    };
    const result = keys.filter(key => under(key) === null);
    for (const key of keys) {
      const target = under(key);
      if (target === null)
        continue;
      let at = result.indexOf(target) + 1;
      while (at < result.length && (properties[result[at]]?.["x-beside"] === true || under(result[at]) === target))
        at++;
      result.splice(at, 0, key);
    }
    return result;
  }

  // Whether a setting waits for the user's own Save or card instead of
  // going live or being set from the launcher: `x-applyOnSave` (Hyprland's
  // mode) or `x-takeover` (the locker, idle, polkit, the greeter), whose
  // effect is a takeover
  function waitsForUser(schema) {
    return schema?.["x-applyOnSave"] === true || schema?.["x-takeover"] === true;
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
  // it, down through nested objects (not array items). `rows` and
  // `compositorAllows` don't resolve: give them a resolved schema
  // (`resolved(schema, schema)`)
  function resolved(node, schema) {
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
      properties[key] = root.resolved(prop, schema);
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

  // `x-hintedIf` (a compositor condition): whether its row is hidden. A
  // failing key hides it, unless every failing key is a
  // `/$supports.<capability>` the backend names an upgrade for
  // (hintOf(capability), CompositorManager.unsupportedHint, isn't ""):
  // then the row is greyed out as an `x-enabledIf` one (failingKey says
  // why)
  function hintedHides(condition, valueOf, hintOf) {
    if (!condition)
      return false;
    return Object.keys(condition).some(key => {
      const one = {};
      one[key] = condition[key];
      if (root.showIfHolds(one, valueOf))
        return false;
      return !key.startsWith("/$supports.") || hintOf(key.slice("/$supports.".length)) === "";
    });
  }

  // Whether the setting at `path` (from the schema's root) can be set at
  // all under the running compositor: the `/$` keys (SettingsManager.
  // configValueAt) of the `x-showIf`, `x-enabledIf` and `x-hintedIf` of its
  // section, the objects it's in and its own hold. Other keys depend on
  // the config, and are left out.
  function compositorAllows(schema, path, valueOf) {
    let node = schema;
    for (const key of path) {
      node = node?.properties?.[key];
      if (!node)
        return false;
      const condition = Object.assign({}, node["x-showIf"] ?? {}, node["x-enabledIf"] ?? {}, node["x-hintedIf"] ?? {});
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
  // first. A nested object with `x-row` is one row (and the rows it draws)
  // on a card of its own, titled by the object. A card holding a field or
  // `x-row` object marked `x-wide` spans both columns (`wide`).
  function groups(schema, sectionKey) {
    const section = root.resolved(schema.properties[sectionKey], schema);
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
          // A theme integration's card header shows its hookup status
          // (SettingsGroupCard reads `hookup`)
          if (prop["x-hookup"])
            card.hookup = key;
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
        if (objectRows[0]?.kind === "group" && objectRows[0].title === prop["x-group"])
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
      // An object one row draws (`x-row`) is that row on a card of its
      // own, titled by it (its `x-wide` widens the card)
      if (prop["x-row"]) {
        cardFor(prop.title ?? key, {
          "defaultTitle": prop.title ?? key,
          "description": prop.description ?? "",
          "section": sectionTitle,
          "path": [sectionKey, key],
          "showIf": prop["x-showIf"] ?? null,
          "showIfParent": [sectionKey]
        }).rows.push(...root.rows({
          "properties": {
            [key]: prop
          }
        }, [sectionKey]));
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
      root.withIntro(own, section["x-intro"]);
    for (const key of nested) {
      const prop = section.properties[key];
      const card = prop["x-intro"] ? cards.find(card => card.path.join(".") === sectionKey + "." + key && card.title === (prop.title ?? key)) : null;
      if (card)
        root.withIntro(card, prop["x-intro"]);
    }
    return result.concat(cards);
  }

  // Gives a card its `x-intro`: the name, or `{ file, setup: [keys] }`.
  // With `setup` (keys relative to the card's object), the rows named stay
  // under the intro and every other row goes behind a fold: a `Settings`
  // group row (`fold: true`, `foldRows` the rows behind it, its path
  // `<card key>:settings` so the open state is kept like an `x-fold`'s)
  // and each row behind it `foldedBy` that path (`foldedIn` where it
  // already has an `x-fold` of its own). No row left over: no fold
  function withIntro(card, intro) {
    if (typeof intro === "string") {
      card.intro = intro;
      return;
    }
    card.intro = intro.file;
    const setup = intro.setup ?? [];
    const head = card.rows.filter(row => row.kind !== "group" && setup.includes(row.path.slice(card.path.length).join(".")));
    const rest = card.rows.filter(row => !head.includes(row));
    if (!rest.some(row => row.kind !== "group"))
      return;
    const fold = card.key + ":settings";
    for (const row of rest) {
      if (row.foldedBy || row.fold === true)
        row.foldedIn = fold;
      else
        row.foldedBy = fold;
    }
    card.rows = head.concat([
      {
        "kind": "group",
        "title": "Settings",
        "path": [fold],
        "showIf": null,
        "fold": true,
        "foldRows": rest
      }
    ], rest);
  }

  // A category's cards in page order: its own `cards` marked `first`, its
  // sections' (`groups`), then its other own `cards`, in order. Wide cards
  // ahead of every narrow one stay at the top; any other goes to the
  // bottom, so none cuts the columns partway down (`methods/ColumnSplit`
  // lays them out)
  function categoryGroups(schema, category) {
    const all = [].concat(...(category?.sections ?? []).map(section => root.groups(schema, section)));
    const owns = Array.prototype.filter.call(category?.cards ?? [], own => own.first).concat(Array.prototype.filter.call(category?.cards ?? [], own => !own.first));
    let firsts = 0;
    for (const own of owns)
      all.splice(own.first ? firsts++ : all.length, 0, {
        "kind": "card",
        "key": category.name + ":" + own.card,
        "card": own.card,
        "folds": false,
        "wide": true,
        "title": own.title || category.name,
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
  // object; the row drawing it for one another row draws, `drawnBy`;
  // `folds` every fold it's inside to open: the `x-fold` (`foldedBy`) and
  // the fold of the card's settings behind its `x-intro` (`foldedIn`), [] for
  // none), or null when no card shows it. `valueOf` as `categories`
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
          "row": exact ? (exact.drawnBy ? exact.drawnBy.split(".") : exact.path) : null,
          "folds": [exact?.foldedBy, exact?.foldedIn].filter(Boolean)
        };
      }
    }
    return null;
  }

  // [{ name, icon, cards: [{ card, title, first }], sections: [key], links:
  // [page type] }]: the root's `x-categories` in order (`icon`, and
  // `cards`, the category's own hand-built cards: settings/<card>Card.qml,
  // wide, titled `title` in the sidebar, ahead of the sections' with
  // `first`), then any
  // other `x-category` in schema order. A section without `x-category` is
  // a category of its own. A declared category with no sections and no
  // card is left out, as is one whose `showIf` fails and a section whose
  // own `x-showIf` does (`/`-rooted keys, read by `valueOf`; e.g. the
  // compositor's, as SettingsManager.configValueAt reads them; without
  // `valueOf`, both are kept).
  function categories(schema, valueOf) {
    const make = (name, declared) => ({
          "name": name,
          "icon": declared?.icon ?? "settings",
          "cards": Array.prototype.map.call(declared?.cards ?? [], own => Object.assign({
              "card": own.card,
              "title": own.title ?? ""
            }, own.first === true ? {
              "first": true
            } : {})),
          "sections": [],
          "links": []
        });
    const declared = Array.prototype.filter.call(schema?.["x-categories"] ?? [], category => !valueOf || showIfHolds(category.showIf, valueOf));
    const hidden = Array.prototype.filter.call(schema?.["x-categories"] ?? [], category => !declared.includes(category)).map(category => category.name);
    const result = declared.map(category => make(category.name, category));
    for (const key in schema?.properties ?? {}) {
      const section = schema.properties[key];
      if (section.type !== "object" || section["x-settings"] === false || groups(schema, key).length === 0)
        continue;
      if (valueOf && !showIfHolds(section["x-showIf"], valueOf))
        continue;
      const name = section["x-category"] ?? section.title ?? key;
      if (hidden.includes(name))
        continue;
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
    return result.filter(c => c.sections.length > 0 || c.cards.length > 0);
  }
}
