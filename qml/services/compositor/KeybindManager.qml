pragma Singleton
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

/*
 * KeybindManager reads the keybinds the compositor has registered
 * (CompositorManager.withBinds). Each bind's `description` is its label (on
 * Hyprland's Lua config every action is an opaque `__lua` dispatcher). A
 * "Section: Label" prefix picks the overlay section. It also names the
 * bind actions (labels, icons, arguments) and shows keys and combos.
 *
 * The Keybinds page's editor of axiom's own binds is its `editor`
 * (KeybindEditor), the page's view state its `page` (KeybindsPageState).
 */
QtObject {
  id: root

  readonly property KeybindEditor editor: KeybindEditor {
    id: keybindEditor
    page: pageState
  }
  readonly property KeybindsPageState page: KeybindsPageState {
    id: pageState
    editor: keybindEditor
  }

  // [{ title, undescribed, binds: [{ label, combos: [{ mods: ["SUPER", "SHIFT"], keys: ["H", "←"] }], axiom, user, ids, action, overrides }] }]
  // `title` is "" for binds with no section (shown as "Other"); `undescribed`
  // marks the section of binds without a description (label ""). A row's
  // `axiom` / `user` say whether any of its binds are axiom's own (applied
  // from Keybinds.binds) / from the user's compositor config; `ids` are its
  // keys (BindKeys.keyId), `action` the first axiom bind's action and
  // `overrides` the label of an axiom bind skipped because the row holds
  // its key. Numbered runs and direction sets are folded (BindRows).
  readonly property var keybindings: root._buildKeybindings(root._entries, root._axiomIds, root._skippedLabels)

  // What each bind action is (labels, sections, calls, arguments; the
  // BindActions functions read it): the daemon's table
  // (compositor.bindActions), read again after each hello, since a new
  // binary may bring another; null until it answers
  readonly property var actionTable: root._actionTable
  property var _actionTable: null

  function _readActionTable() {
    BackendManager.call("compositor.bindActions", {}, (error, result) => {
      if (!error)
        root._actionTable = result;
    });
  }

  property Connections _hello: Connections {
    target: BackendManager
    function onGreeted() {
      root._readActionTable();
    }
  }

  readonly property var _actionSchema: ConfigManager.configSchema?.definitions?.Keybind?.properties?.action ?? ({})
  readonly property var actions: _actionSchema.enum ?? []
  // Action -> its label (translated; the schema's labels are keys already)
  readonly property var _actionLabelSchema: _actionSchema["x-enumLabels"] ?? ({})
  readonly property var actionLabels: Object.keys(_actionLabelSchema).reduce((labels, action) => {
    const english = _actionLabelSchema[action];
    labels[action] = I18n.tr(english);
    return labels;
  }, {})

  // A bind's "Only when" parts, from the schema: [{ field, title, options,
  // labels, multi }], titles and labels translated; `multi` (the
  // compositors) holds a list, any of which will do
  readonly property var conditionFields: ["whenCompositors", "whenLayout", "whenMonitors"].map(field => {
    const schema = ConfigManager.configSchema?.definitions?.Keybind?.properties?.[field] ?? ({});
    const options = schema.enum ?? schema.items?.enum ?? [];
    const labels = {};
    for (const value of options)
      labels[value] = I18n.tr(schema["x-enumLabels"]?.[value] ?? value);
    return {
      "field": field,
      "title": I18n.tr(schema.title ?? field),
      "options": options,
      "labels": labels,
      "multi": schema.type === "array"
    };
  })

  // A bind's condition in words, its parts set joined ("" for none)
  function conditionText(bind) {
    return root.conditionFields.map(part => [].concat(bind?.[part.field] ?? []).filter(value => value !== "").map(value => part.labels[value] ?? value).join(" / ")).filter(text => text !== "").join(" · ");
  }

  // The action picker's categories, in tab order ("" is All). `exec` is
  // filed under Apps there; everything else by its section on the page.
  // I18n.tr("Axiom") I18n.tr("System") I18n.tr("Tools") I18n.tr("Apps")
  // I18n.tr("Media") I18n.tr("Window") I18n.tr("Workspace")
  // I18n.tr("Special") I18n.tr("Custom")
  readonly property var actionSections: ["Axiom", "System", "Tools", "Apps", "Media", "Window", "Workspace", "Special", "Custom"]

  // A reference section's title as shown (its chip and its card)
  function sectionTitle(section) {
    return section.undescribed ? I18n.tr("Undescribed") : (section.title ? I18n.tr(section.title) : I18n.tr("Other"));
  }

  // Material Symbols per reference section, by title ("" is Other)
  function sectionIcon(title) {
    return root._sectionIcons[title] ?? "keyboard";
  }
  readonly property var _sectionIcons: ({
      "Axiom": "dashboard",
      "System": "settings",
      "Tools": "construction",
      "Apps": "apps",
      "Media": "music_note",
      "Window": "select_window",
      "Workspace": "grid_view",
      "Special": "star",
      "Custom": "tune",
      "": "more_horiz"
    })

  // [{ action, label, section, icon }], one per action, in schema order
  // The actions the running compositor can do (the table's needs); a saved
  // bind with another keeps it, flagged in `issues`
  readonly property var actionInfo: root.actions.filter(action => BindActions.supported(root.actionTable, action, CompositorManager.supports)).map(action => ({
        "action": action,
        "label": root.actionLabels[action] ?? action,
        "section": action === "exec" ? "Apps" : BindActions.sectionFor(root.actionTable, action),
        "icon": root.actionIcon(action)
      }))

  // An action's Material Symbol (the table's icons; the picker, its
  // button, a tile)
  function actionIcon(action) {
    return BindActions.iconOf(root.actionTable, action);
  }

  // What an action's free-text argument is, for its placeholder
  function argumentKind(action) {
    return BindActions.argumentKind(root.actionTable, action);
  }

  function needsArgument(action) {
    return BindActions.needsArgument(root.actionTable, action);
  }

  // How many workspaces a number can name: the layout's, or ten where the
  // compositor makes them itself (CompositorManager.dynamicWorkspaces)
  readonly property int workspaceKeys: CompositorManager.dynamicWorkspaces ? 10 : WorkspacesConfig.size

  // The choices for an action's argument, or null for free text
  function argumentOptions(action) {
    switch (BindActions.argumentKind(root.actionTable, action)) {
    case "direction":
      return ["left", "right", "up", "down"];
    case "workspace":
      return Array.from({
        "length": root.workspaceKeys
      }, (_, i) => String(i + 1));
    case "screenshot":
      return ["region", "window", "screen"];
    case "edgeMenu":
      return EdgeMenusConfig.menus.map(menu => menu.id).filter(id => id);
    case "dock":
      return DockConfig.docks.map(dock => dock.id);
    case "bar":
      return ["focused"].concat(BarsConfig.savedBars.filter(bar => bar.autoHide !== "never").map(bar => bar.id));
    case "view":
      return OverlayConfig.views.filter(view => view.visible !== false).map(view => view.name || view.type).concat(["Layouts"]).filter((name, i, all) => all.indexOf(name) === i);
    case "theme":
      // A family by its first variant (theme set applies the one for the
      // light/dark mode)
      return ["random"].concat(ThemeManager.themeFamilies.map(family => family.dark || family.light));
    }
    return null;
  }

  // The labels of argumentOptions' choices, by value, where they aren't
  // the value itself (null for none)
  function argumentLabels(action) {
    if (BindActions.argumentKind(root.actionTable, action) !== "theme")
      return null;
    return ThemeManager.themeFamilies.reduce((labels, family) => {
      labels[family.dark || family.light] = family.label;
      return labels;
    }, {
      "random": I18n.tr("Random")
    });
  }

  // The choices for an action's call, or null when it has none
  function callOptions(action) {
    return BindActions.hasCalls(root.actionTable, action) ? ["toggle", "open", "close"] : null;
  }

  // A call's label for an action (a recording bind starts or stops it; one
  // whose open call is `enable`, caffeine or Wi-Fi, turns it on or off)
  function callLabels(action) {
    const record = action === "screenRecord";
    const onOff = !record && root.actionTable?.calls?.[action]?.open === "enable";
    // A bar's toggle pins it shown; open shows it for a moment
    if (action === "bar")
      return {
        "toggle": I18n.tr("Pin or unpin"),
        "open": I18n.tr("Show"),
        "close": I18n.tr("Hide")
      };
    return {
      "toggle": I18n.tr("Toggle"),
      "open": record ? I18n.tr("Start") : onOff ? I18n.tr("Turn on") : I18n.tr("Open"),
      "close": record ? I18n.tr("Stop") : onOff ? I18n.tr("Turn off") : I18n.tr("Close")
    };
  }

  // Keys the compositor binds outside axiom, by BindKeys.keyId: every bind
  // it reports, less the saved axiom binds the layer applied
  readonly property var userKeyCounts: BindKeys.userKeyCounts(root._entries, root._appliedBinds)

  // What a bind's "Only when" is decided on (BindConditions; the
  // daemon's bindFacts): the compositor, whether any output is a strip,
  // the grid layout, dynamic workspaces, the connected outputs
  readonly property var conditionFacts: ({
      "kind": CompositorManager.kind,
      "strips": CompositorManager.supports.stripsAlways === true || (CompositorManager.supports.strips === true && WorkspacesConfig.hasStrips),
      "grid": WorkspacesConfig.grid,
      "dynamic": CompositorManager.supports.dynamicWorkspaces === true,
      "outputs": CompositorManager.outputs.map(output => output.name)
    })

  // The saved binds bound now: not paused, their "Only when" holding (the
  // daemon binds only these)
  readonly property var boundBinds: KeybindsConfig.activeBinds.filter(bind => BindConditions.holds(bind, root.conditionFacts))

  // The saved axiom binds the runtime layer applied (the rest it skipped)
  readonly property var _appliedBinds: root.boundBinds.filter(bind => CompositorConfigManager.isComplete(bind) && !root._skippedIds.includes(BindKeys.keyId(bind.key)))
  // The keys the runtime layer skipped, by BindKeys.keyId
  readonly property var _skippedIds: CompositorConfigManager.skippedKeys.map(key => BindKeys.keyId(key))

  // Their keys, by BindKeys.keyId: { "64:return": bind }
  readonly property var _axiomIds: root._appliedBinds.reduce((ids, bind) => {
    const id = BindKeys.keyId(bind.key);
    if (id !== "")
      ids[id] = bind;
    return ids;
  }, {})

  // The saved axiom binds skipped because the user's config holds their
  // key, their labels by key: { "64:q": "Close window" }
  readonly property var _skippedLabels: root.boundBinds.reduce((labels, bind) => {
    const id = BindKeys.keyId(bind.key);
    if (id !== "" && root._skippedIds.includes(id) && labels[id] === undefined)
      labels[id] = root.bindLabel(bind);
    return labels;
  }, {})

  // A bind's label: its own (less a "Section:" prefix), else its action's
  function bindLabel(bind) {
    const own = BindActions.splitDescription(bind?.description).label;
    if (own !== "")
      return own;
    return BindActions.defaultLabel(root.actionTable, bind) || (root.actionLabels[bind?.action] ?? "");
  }

  readonly property var _keyNames: ({
      "mouse_left": "Scroll ←",
      "mouse_right": "Scroll →",
      "super_l": "Super L",
      "super_r": "Super R",
      "control_l": "Ctrl L",
      "control_r": "Ctrl R",
      "alt_l": "Alt L",
      "alt_r": "Alt R",
      "shift_l": "Shift L",
      "shift_r": "Shift R"
    })

  // Every bind the compositor reported (CompositorManager.withBinds)
  property var _entries: []

  function refresh() {
    if (!CompositorManager.supports.bindMerge)
      return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    CompositorManager.withBinds(binds => {
      root._reading = false;
      if (binds) {
        root._entries = binds;
      }
      if (root._readAgain) {
        root._readAgain = false;
        root.refresh();
      }
    });
  }

  property bool _reading: false
  property bool _readAgain: false

  // After binds were applied at runtime, which no compositor announces
  function refreshSoon() {
    _refreshDelay.restart();
  }

  property Timer _refreshDelay: Timer {
    interval: 500
    onTriggered: root.refresh()
  }

  function _buildKeybindings(entries, axiomIds, skippedLabels) {
    const sections = [];
    const sectionByTitle = {};
    const rowByKey = {};
    let undescribed = null;

    for (const entry of entries) {
      const description = BindActions.splitDescription(entry.description);
      // null: undescribed
      const title = description.label === "" ? null : description.section || entry.submap || "";
      const label = description.label;

      let section = title === null ? undescribed : sectionByTitle[title];
      if (!section) {
        section = {
          title: title ?? "",
          undescribed: title === null,
          binds: []
        };
        if (title === null)
          undescribed = section;
        else {
          sectionByTitle[title] = section;
          sections.push(section);
        }
      }

      const mods = BindKeys.decodeMods(entry.modmask);
      const key = root._formatKey(entry.key);
      const rowKey = `${section.title}\u0000${label}`;
      const id = BindKeys.entryId(entry);
      // Axiom's runtime binds are never in a submap
      const axiomBind = entry.submap ? undefined : axiomIds[id];
      const isAxiom = !!axiomBind;

      // Undescribed binds each get their own row, since they share an empty label.
      // Alternatives with the same modifiers share a combo: Super + H / ←.
      const row = label ? rowByKey[rowKey] : undefined;
      if (row) {
        row.axiom = row.axiom || isAxiom;
        row.user = row.user || !isAxiom;
        row.ids.push(id);
        row.action = row.action || (axiomBind?.action ?? "");
        row.overrides = row.overrides || (isAxiom ? "" : skippedLabels[id] ?? "");
        const combo = row.combos.find(c => c.mods.join("+") === mods.join("+"));
        if (!combo)
          row.combos.push({
            mods: mods,
            keys: [key]
          });
        else if (!combo.keys.includes(key))
          combo.keys.push(key);
        continue;
      }
      const newRow = {
        label: label,
        combos: [
          {
            mods: mods,
            keys: [key]
          }
        ],
        axiom: isAxiom,
        user: !isAxiom,
        ids: [id],
        action: axiomBind?.action ?? "",
        overrides: isAxiom ? "" : skippedLabels[id] ?? ""
      };
      if (label)
        rowByKey[rowKey] = newRow;
      section.binds.push(newRow);
    }

    if (undescribed)
      sections.push(undescribed);
    for (const section of sections)
      section.binds = BindRows.collapseDirections(BindRows.collapseNumbered(section.binds));
    return sections;
  }

  // A combo as shown on the page ("SUPER + mouse:272" -> "SUPER + LMB")
  function displayCombo(combo) {
    const key = String(combo ?? "").trim();
    return key === "" ? "" : key.split("+").map(part => root.displayKey(part.trim())).join(" + ");
  }

  // A key name as shown on a keycap ("space" -> "Space", "left" -> "←")
  function displayKey(key) {
    return _formatKey(String(key ?? ""));
  }

  function _formatKey(key) {
    if (root._keyNames[key.toLowerCase()] !== undefined)
      return root._keyNames[key.toLowerCase()];
    const mapped = KeyMap.labelOf(key);
    if (mapped !== "")
      return mapped;
    // XF86AudioPause -> Pause, XF86MonBrightnessUp -> Brightness Up
    if (key.startsWith("XF86"))
      return Utils.spaceWords(key.slice(4).replace(/^(Audio|Mon)(?=[A-Z])/, ""));
    if (key.length === 1)
      return key.toUpperCase();
    return key.charAt(0).toUpperCase() + key.slice(1);
  }

  property Connections _compositorEvents: Connections {
    target: CompositorManager

    function onConfigReloaded() {
      root.refresh();
    }
  }

  // Read as soon as the compositor is known to list its binds: created
  // early in the shell's start, this can come before
  // CompositorManager.supports is filled in, and a refresh then does nothing
  readonly property bool _canRead: CompositorManager.supports.bindMerge === true
  on_CanReadChanged: refresh()
  // A detached-mode Save re-applies binds by eval, with no reload to announce it
  on_AppliedBindsChanged: refreshSoon()
  Component.onCompleted: {
    refresh();
    root._readActionTable();
  }
}
