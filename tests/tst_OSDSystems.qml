import QtQuick
import QtTest
import qs.components.methods
import "osd/index.js" as Timelines

// The OSD's timelines (tests/osd/): each row runs states through a
// system's definition (systems/<Name>/<Name>.qml, loaded by its path) and
// OSDEngine, step by step, and checks what each step shows and what a host
// does with it. The row format: docs/dev/features/osd.md › Engine ›
// Timelines. Rows of a system with no folder yet are skipped
TestCase {
  id: root
  name: "OSDSystems"

  RepoFiles {
    id: repo
  }

  // Definitions loaded, by system (null: no folder)
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
    else if (!/No such file|not found|Cannot open/i.test(component.errorString()))
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
      if (!def)
        skip(type + " has no system folder yet");
      def.options = (row.options ?? {})[type] ?? row.options ?? {};
      defs[type] = def;
    }
    // Each system's state, by key
    const states = {};
    systems.forEach(type => states[type] = {});
    const tileNow = (system, key) => defs[system] ? OSDEngine.tileOf(defs[system], key, states[system]?.[key]) : {};
    const host = {
      "card": row.host?.card ?? null,
      "ring": row.host?.ring ?? null
    };
    const against = (shown, what) => OSDEngine.arbitrate(Object.assign({}, shown, {
        "part": OSDEngine.partOf(defs[shown.system], shown.key),
        "card": shown === host.card,
        "tile": tileNow(shown.system, shown.key)
      }), Object.assign({}, what, {
        "tile": tileNow(what.system, what.key)
      }), what.at - shown.at, defs);
    // What a host does with a change: OSDHost's order
    const decide = what => {
      const placed = {
        "system": what.system,
        "key": what.key,
        "at": what.at
      };
      if (what.show === "card") {
        if (!host.card) {
          host.card = placed;
          return "open";
        }
        const d = against(host.card, what);
        if (d === "replace")
          host.card = placed;
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
        const what = OSDEngine.judge(def, e.key, before[e.key], after[e.key], {
          "at": at,
          "byUser": step.byUser === true,
          "settled": settled !== false,
          "before": before,
          "after": after
        });
        if (what)
          changes.push(Object.assign({
            "system": system
          }, what));
      }
      states[system] = after;
      changes.forEach(what => what.host = decide(what));

      const expected = step.expect === undefined || step.expect === "none" ? [] : Array.isArray(step.expect) ? step.expect : [step.expect];
      compare(changes.map(c => c.key + ":" + c.show), expected.map((x, j) => (x.key ?? changes[j]?.key) + ":" + x.show), where + ": what shows");
      expected.forEach((x, j) => {
        const what = changes[j];
        for (const field of Object.keys(x)) {
          if (field === "tile")
            root._holds(OSDEngine.tileOf(def, what.key, after[what.key]), x.tile, where + " tile");
          else if (field === "card")
            root._holds(OSDEngine.cardOf(def, what, after), x.card, where + " card");
          else
            root._holds(what[field], x[field], where + " " + field);
        }
      });
    });
  }
}
