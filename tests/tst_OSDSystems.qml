import QtQuick
import QtTest
import qs.components.methods
import "osd/index.js" as Timelines

// The OSD's timelines (tests/osd/): each row runs states through a
// system's definition (systems/<Name>/<Name>.qml, loaded by its path) and
// OSDEngine, step by step, and checks what each step shows and what a host
// does with it. The row format: docs/dev/features/osd.md › Engine ›
// Timelines. A row of a system with no folder fails
TestCase {
  id: root
  name: "OSDSystems"

  RepoFiles {
    id: repo
  }

  // Definitions loaded, by system (null: it doesn't load)
  property var _defs: ({})

  function definition(type) {
    if (root._defs[type] !== undefined)
      return root._defs[type];
    const component = Qt.createComponent(repo.url("qml/components/surfaces/osd/systems/" + type + "/" + type + ".qml"));
    let def = null;
    if (component.status === Component.Ready)
      def = component.createObject(root, {
        "type": type
      });
    else
      fail(type + " doesn't load: " + component.errorString());
    const defs = Object.assign({}, root._defs);
    defs[type] = def;
    root._defs = defs;
    return def;
  }

  function test_timelines_data() {
    const out = [];
    for (const file of Object.keys(Timelines.files))
      for (const row of Timelines.files[file])
        out.push({
          "tag": file + ": " + row.name,
          "file": file,
          "row": row
        });
    return out;
  }

  // Whether `actual` holds every field of `expected` (objects compared
  // field by field, the rest exactly)
  function _holds(actual, expected, where) {
    if (expected === null || typeof expected !== "object" || Array.isArray(expected)) {
      compare(actual, expected, where);
      return;
    }
    verify(actual !== null && actual !== undefined, where + ": missing");
    for (const field of Object.keys(expected))
      root._holds(actual[field], expected[field], where + "." + field);
  }

  function test_timelines(data) {
    const row = data.row;
    const systems = row.systems ?? [data.file];
    const defs = {};
    for (const type of systems) {
      const def = root.definition(type);
      verify(def !== null, type + " has no system folder");
      def.options = (row.options ?? {})[type] ?? row.options ?? {};
      defs[type] = def;
    }
    // Each system's state, by key
    const states = {};
    systems.forEach(type => states[type] = {});
    // What each is judged against, as its watcher keeps it
    // (OSDEngine.remember: a gap's value kept)
    const judged = {};
    systems.forEach(type => judged[type] = {});
    const tileNow = (system, key) => defs[system] ? OSDEngine.contextTile(defs[system], key, states[system]) : {};
    // What's out: the whole judged change (with its system and its tile
    // as it came, as OSDHost keeps it) of the card and of the ringed
    // tile; a row's own start gives { system, key, at }
    const host = {
      "card": row.host?.card ? Object.assign({
        "card": true
      }, row.host.card) : null,
      "ring": row.host?.ring ? Object.assign({
        "card": false
      }, row.host.ring) : null
    };
    const against = (shown, what) => OSDEngine.arbitrate(Object.assign({}, shown, {
        "part": OSDEngine.partOf(defs[shown.system], shown.key),
        "card": shown === host.card,
        "tile": shown.tile ?? tileNow(shown.system, shown.key)
      }), Object.assign({}, what, {
        "tile": tileNow(what.system, what.key)
      }), what.at - shown.at, defs);
    // What a host does with a change: OSDHost's order. A card shown
    // rings its tile while the icons are out (a ring is: `_showCard`)
    const decide = what => {
      const placed = Object.assign({}, what, {
        "tile": tileNow(what.system, what.key)
      });
      const showCard = () => {
        host.card = placed;
        if (host.ring && OSDEngine.partOf(defs[what.system], what.key) === "tile")
          host.ring = Object.assign({}, placed, {
            "card": false
          });
      };
      if (what.show === "card") {
        if (!host.card) {
          showCard();
          return "open";
        }
        const d = against(host.card, what);
        if (d === "replace")
          showCard();
        return d;
      }
      let out = "";
      if (host.card) {
        out = against(host.card, what);
        if (out === "suppress")
          return out;
        if (out === "retract")
          host.card = null;
      }
      if (what.show === "level")
        return out || "open";
      if (host.ring && against(host.ring, what) === "keep")
        return out === "retract" ? out : "keep";
      host.ring = placed;
      return out || "ring";
    };

    let at = 0;
    row.steps.forEach((step, i) => {
      const where = data.tag + " #" + i;
      const system = step.system ?? systems[0];
      const def = defs[system];
      verify(def, where + ": " + system + " isn't one of the row's systems");
      at = step.at ?? at + 3000;
      const before = states[system];
      const after = Object.assign({}, before);
      for (const key of Object.keys(step.state ?? {})) {
        if (step.state[key] === null)
          delete after[key];
        else
          after[key] = step.state[key];
      }
      const changes = [];
      for (const e of def.exposes) {
        const settled = typeof step.settled === "object" ? step.settled[e.key] : step.settled;
        const what = OSDEngine.judge(def, e.key, judged[system][e.key], after[e.key], {
          "at": at,
          "byUser": step.byUser === true,
          "settled": settled !== false,
          "before": judged[system],
          "after": after
        });
        if (what)
          changes.push(Object.assign({
            "system": system
          }, what));
      }
      states[system] = after;
      judged[system] = OSDEngine.remember(def, judged[system], after);
      changes.forEach(what => what.host = decide(what));

      const expected = step.expect === undefined || step.expect === "none" ? [] : Array.isArray(step.expect) ? step.expect : [step.expect];
      compare(changes.map(c => c.key + ":" + c.show), expected.map((x, j) => (x.key ?? changes[j]?.key) + ":" + x.show), where + ": what shows");
      expected.forEach((x, j) => {
        const what = changes[j];
        for (const field of Object.keys(x)) {
          if (field === "tile")
            root._holds(OSDEngine.tileOf(def, what.key, after[what.key]), x.tile, where + " tile");
          else if (field === "opens")
            compare(OSDEngine.opens(def.options, def, what, row.onScreenChanges === true), x.opens, where + " opens");
          else if (field === "action")
            root._holds(def.actionOf(what.key, after[what.key]), x.action, where + " action");
          else if (field === "card")
            root._holds(OSDEngine.cardOf(def, what, after), x.card, where + " card");
          else
            root._holds(what[field], x[field], where + " " + field);
        }
      });
      // Tiles as they are, changed or not
      for (const key of Object.keys(step.tiles ?? {}))
        root._holds(OSDEngine.tileOf(def, key, after[key]), step.tiles[key], where + " tiles." + key);
    });
  }

  // A system's bars in the settings (OSDConfig.barRows, an OSD's
  // barOrder: OSDParts.barKey over its `x-barNames`) are keyed as its
  // definition's `exposes` keys them: a list's entries, one of each kind,
  // or a one-bar system's one
  function test_barKeys() {
    const schema = repo.json("qml/config/json/config.schema.json");
    let checked = 0;
    for (const option of schema.definitions.OSDSystem.oneOf) {
      const item = schema.definitions[option.$ref.replace("#/definitions/", "")];
      const spec = item["x-barNames"];
      if (!spec)
        continue;
      const type = item.properties.type.const;
      const def = root.definition(type);
      let entries = [];
      if (OSDParts.oneBar(spec)) {
        def.options = {};
      } else {
        entries = item.properties[spec.from].items.properties[spec.by].enum.map((kind, i) => ({
              "id": "bar" + i,
              [spec.by]: kind
            }));
        def.options = {
          [spec.from]: entries
        };
      }
      const expected = OSDParts.oneBar(spec) ? [spec.bar] : entries.map(entry => OSDParts.barKey(spec, entry));
      compare(def.exposes.filter(e => e.part === "bar").map(e => e.key), expected, type + "'s bar keys");
      checked++;
    }
    verify(checked >= 2, "Audio and Brightness at least");
  }
}
