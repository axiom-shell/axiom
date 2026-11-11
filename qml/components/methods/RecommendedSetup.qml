pragma Singleton
import QtQuick

// The Recommended setup list of managed mode (onboarder and Compositor
// card), worked out from the schema's `x-recommended` annotations: which
// entries it has, which rows are available, ticked by default or done, and
// the ordered plan of steps an Apply runs. Pure: the facts it needs come in
// as arguments and the reasons go out as codes, which the hosts translate
// (RecommendedSetupManager, forms/RecommendedSetupList). No files,
// processes or services.
QtObject {
  id: root

  // The step each path takes when it isn't a plain commit (the others are
  // `commit`; a section with `installed` is `apps`); each is its own code
  // path in RecommendedSetupManager
  readonly property var stepOfPath: ({
      "ScreenSharing.enabled": "portal",
      "Greeter.enabled": "greeter"
    })
  // Rows that come first of their step, in this order, however the schema
  // is ordered
  readonly property var leadPaths: ["Compositor.mode"]
  // Rows are listed commit, portal, apps, greeter
  readonly property var stepOrder: ({
      "commit": 0,
      "portal": 1,
      "apps": 2,
      "greeter": 3
    })

  // The boolean fields of a ThemeIntegrations-like section node that are
  // recommended (`x-recommended` not false), in schema order
  function _recommendedKeys(section) {
    const keys = [];
    const properties = section?.properties ?? {};
    for (const key in properties) {
      const field = properties[key];
      if (field.type === "boolean" && field["x-recommended"] !== false)
        keys.push(key);
    }
    return keys;
  }

  // The list's entries from the built schema: [{ id, path, step, value,
  // label, detail, keys }]. A field with `x-recommended` is one entry (id and
  // path "Section.key", label the section's title, detail the value's
  // `x-enumLabels` else the field's title); a section with `installed` is
  // one `apps` entry (id and path "Section", `keys` its recommended boolean
  // fields). Commit rows first in schema order, then portal, apps, greeter.
  function entries(schema) {
    const found = [];
    const sections = schema?.properties ?? {};
    for (const section in sections) {
      const node = sections[section];
      if (!node?.properties)
        continue;
      if (node["x-recommended"] === "installed") {
        found.push({
          "id": section,
          "path": section,
          "step": "apps",
          "value": true,
          "label": node.title ?? section,
          "detail": "",
          "keys": root._recommendedKeys(node)
        });
        continue;
      }
      for (const key in node.properties) {
        const field = node.properties[key];
        if (field["x-recommended"] === undefined)
          continue;
        const path = section + "." + key;
        const value = field["x-recommended"];
        found.push({
          "id": path,
          "path": path,
          "step": root.stepOfPath[path] ?? "commit",
          "value": value,
          "label": node.title ?? section,
          "detail": field["x-enumLabels"]?.[value] ?? field.title ?? key,
          "keys": []
        });
      }
    }
    // Stable by step: the sort key carries the index
    const lead = item => {
      const at = root.leadPaths.indexOf(item.entry.path);
      return at < 0 ? root.leadPaths.length : at;
    };
    return found.map((entry, index) => ({
          "entry": entry,
          "index": index
        })).sort((a, b) => (root.stepOrder[a.entry.step] - root.stepOrder[b.entry.step]) || (lead(a) - lead(b)) || a.index - b.index).map(item => item.entry);
  }

  // The keys of `section` (the ThemeIntegrations schema node) that are
  // recommended and installed. A key counts as installed when its
  // `x-commands` is `[]` (every desktop has it), or when any of its commands
  // (default the key) has `found[command] === true`.
  function appKeys(section, found) {
    return root._recommendedKeys(section).filter(key => {
      const commands = section.properties[key]["x-commands"] ?? [key];
      if (commands.length === 0)
        return true;
      return Array.prototype.some.call(commands, command => found?.[command] === true);
    });
  }

  // Every row by id: { id, path, step, label, detail, value, keys,
  // hookupKeys, done, available, reason, later, checkedByDefault }.
  // `facts`: { config, schema, valueOf, later: [paths], modeAllowed,
  // modeDefault, managedBlocked, portal: { known, installed, axiomInstalled, hookedUp },
  // apps: { installed: [keys], hookups: { key: "done" | "todo" | "none" } },
  // greeter: GreeterManager.status }. `reason` is a code ("" when
  // available or done): unsupported, blocked, missing, noAxiomPortal, noApps, noGreetd,
  // noCompositor, noClone, unknown.
  function rows(entries, facts) {
    const result = {};
    for (const entry of entries) {
      const keys = entry.path.split(".");
      const row = {
        "id": entry.id,
        "path": entry.path,
        "step": entry.step,
        "label": entry.label,
        "detail": entry.detail,
        "value": entry.value,
        "keys": [],
        "hookupKeys": [],
        "done": false,
        "available": true,
        "reason": "",
        "later": false,
        "checkedByDefault": false
      };
      if (entry.step === "commit")
        root._commitRow(row, keys, facts);
      else if (entry.step === "portal")
        root._portalRow(row, keys, facts);
      else if (entry.step === "apps")
        root._appsRow(row, entry, facts);
      else if (entry.step === "greeter")
        root._greeterRow(row, facts);
      row.checkedByDefault = row.available && !row.done && (!row.later || facts.modeDefault === true);
      result[entry.id] = row;
    }
    return result;
  }

  function _commitRow(row, keys, facts) {
    row.later = Array.prototype.includes.call(facts.later ?? [], row.path);
    row.done = Utils.valueAt(facts.config, keys) === row.value;
    if (!SchemaLayout.compositorAllows(facts.schema, keys, facts.valueOf)) {
      row.available = false;
      row.reason = "unsupported";
    } else if (row.later && facts.modeAllowed !== true) {
      row.available = false;
      row.reason = "blocked";
    } else if (row.path === "Compositor.mode" && facts.managedBlocked === true) {
      row.available = false;
      row.reason = "blocked";
    }
  }

  function _portalRow(row, keys, facts) {
    const portal = facts.portal ?? {};
    row.done = Utils.valueAt(facts.config, keys) === true && portal.hookedUp === true;
    if (!portal.known) {
      row.available = false;
      row.reason = "unsupported";
    } else if (!portal.installed) {
      row.available = false;
      row.reason = "missing";
    } else if (!portal.axiomInstalled) {
      row.available = false;
      row.reason = "noAxiomPortal";
    }
  }

  function _appsRow(row, entry, facts) {
    const installed = facts.apps?.installed ?? [];
    const hookups = facts.apps?.hookups ?? {};
    const config = Utils.valueAt(facts.config, [row.path]) ?? {};
    const mine = entry.keys.filter(key => Array.prototype.includes.call(installed, key));
    row.keys = mine.filter(key => config[key] !== true);
    row.hookupKeys = mine.filter(key => hookups[key] === "todo");
    if (mine.length === 0) {
      row.available = false;
      row.reason = "noApps";
      return;
    }
    row.done = row.keys.length === 0 && row.hookupKeys.length === 0;
  }

  function _greeterRow(row, facts) {
    const status = facts.greeter;
    if (status === "installed" || status === "outdated") {
      row.done = true;
      return;
    }
    if (status === "off" || status === "notInstalled")
      return;
    row.available = false;
    row.reason = status === "noGreetd" || status === "noCompositor" || status === "noClone" ? status : "unknown";
  }

  // The ordered plan of an Apply: `checked` is { id: bool }, already
  // resolved. [{ step: "later", path, value, row }] for each ticked later
  // row; { step: "commit", values: { dottedPath: value }, rows: [ids] } (every
  // ticked commit row, ScreenSharing.enabled for a ticked portal row, the
  // app keys of a ticked apps row; never Greeter.enabled, which the install
  // sets, never a done or later row; left out when empty); { step: "hookup",
  // key: "screenSharing", row } and { step: "portal", row }; one { step:
  // "hookup", key, row } per app whose hookup is still to do; { step:
  // "greeter", row } last. [] when nothing is ticked.
  function steps(entries, rows, checked) {
    const on = id => {
      const row = rows[id];
      return checked[id] === true && !!row && row.available && !row.done;
    };
    const plan = [];
    for (const entry of entries) {
      const row = rows[entry.id];
      if (row.later && on(entry.id))
        plan.push({
          "step": "later",
          "path": entry.path,
          "value": entry.value,
          "row": entry.id
        });
    }
    const values = {};
    const commitRows = [];
    for (const entry of entries) {
      const row = rows[entry.id];
      if (!on(entry.id) || row.later)
        continue;
      if (entry.step === "commit") {
        values[entry.path] = entry.value;
        commitRows.push(entry.id);
      } else if (entry.step === "portal") {
        values[entry.path] = true;
        commitRows.push(entry.id);
      } else if (entry.step === "apps" && row.keys.length > 0) {
        for (const key of row.keys)
          values[entry.path + "." + key] = true;
        commitRows.push(entry.id);
      }
    }
    if (commitRows.length > 0)
      plan.push({
        "step": "commit",
        "values": values,
        "rows": commitRows
      });
    for (const entry of entries) {
      if (entry.step === "portal" && on(entry.id)) {
        plan.push({
          "step": "hookup",
          "key": "screenSharing",
          "row": entry.id
        });
        plan.push({
          "step": "portal",
          "row": entry.id
        });
      }
    }
    for (const entry of entries) {
      if (entry.step === "apps" && on(entry.id)) {
        for (const key of rows[entry.id].hookupKeys)
          plan.push({
            "step": "hookup",
            "key": key,
            "row": entry.id
          });
      }
    }
    for (const entry of entries) {
      if (entry.step === "greeter" && on(entry.id))
        plan.push({
          "step": "greeter",
          "row": entry.id
        });
    }
    return plan;
  }

  // What the portal step does after its hookup: "defer" while a share is
  // active (restarting the portal would end it; it takes effect at the next
  // restart or login), else "restart"
  function portalAction(shareActive) {
    return shareActive ? "defer" : "restart";
  }
}
