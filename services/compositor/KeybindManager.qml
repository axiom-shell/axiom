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

  readonly property var _actionSchema: ConfigManager.configSchema?.definitions?.Keybind?.properties?.action ?? ({})
  readonly property var actions: _actionSchema.enum ?? []
  // Action -> its label (translated; the schema's labels are keys already)
  readonly property var _actionLabelSchema: _actionSchema["x-enumLabels"] ?? ({})
  readonly property var actionLabels: Object.keys(_actionLabelSchema).reduce((labels, action) => {
    const english = _actionLabelSchema[action];
    labels[action] = I18n.tr(english);
    return labels;
  }, {})

  // The action picker's categories, in tab order ("" is All). `exec` is
  // filed under Apps there; everything else by its section on the page.
  // I18n.tr("Axiom") I18n.tr("Apps") I18n.tr("Media") I18n.tr("Window")
  // I18n.tr("Workspace") I18n.tr("Special") I18n.tr("Custom")
  readonly property var actionSections: ["Axiom", "Apps", "Media", "Window", "Workspace", "Special", "Custom"]

  // Material Symbols per reference section, by title ("" is Other)
  function sectionIcon(title) {
    return root._sectionIcons[title] ?? "keyboard";
  }
  readonly property var _sectionIcons: ({
      "Axiom": "dashboard",
      "Apps": "apps",
      "Media": "music_note",
      "Window": "select_window",
      "Workspace": "grid_view",
      "Special": "star",
      "Custom": "tune",
      "": "more_horiz"
    })

  // Material Symbols per action (the picker and its button)
  readonly property var _actionIcons: ({
      "launcher": "apps",
      "launcherSearch": "search",
      "overlay": "dashboard",
      "overlayPage": "web_stories",
      "edgeMenu": "side_navigation",
      "dock": "dock_to_bottom",
      "workspaceOverview": "grid_view",
      "powerMenu": "power_settings_new",
      "lock": "lock",
      "toggleDnd": "do_not_disturb_on",
      "clearNotifications": "clear_all",
      "idleInhibit": "coffee",
      "nightLight": "nightlight",
      "nextWallpaper": "wallpaper",
      "workspaceStep": "swap_horiz",
      "moveWindowStep": "move_item",
      "moveWindowStepSilent": "send",
      "workspaceNth": "counter_1",
      "moveWindowNth": "move_item",
      "moveWindowNthSilent": "send",
      "scrollStep": "mouse",
      "focusDir": "center_focus_strong",
      "moveWindowDir": "open_with",
      "resizeWindow": "open_in_full",
      "closeWindow": "close",
      "fullscreen": "fullscreen",
      "toggleFloat": "picture_in_picture",
      "pin": "push_pin",
      "centerWindow": "center_focus_weak",
      "toggleGroup": "tab_group",
      "pseudo": "picture_in_picture_alt",
      "toggleSplit": "splitscreen_right",
      "stripSwapColumn": "swap_horiz",
      "stripWider": "width_wide",
      "stripNarrower": "width_normal",
      "stripFit": "fit_screen",
      "stripConsume": "move_group",
      "stripCenter": "vertical_align_center",
      "windowSwitcher": "tab",
      "windowSwitcherReverse": "tab",
      "mouseDrag": "drag_pan",
      "mouseResize": "drag_handle",
      "toggleSpecial": "star",
      "moveToSpecial": "star_half",
      "restartShell": "restart_alt",
      "volumeUp": "volume_up",
      "volumeDown": "volume_down",
      "toggleMute": "volume_off",
      "toggleMicMute": "mic_off",
      "brightnessUp": "brightness_high",
      "brightnessDown": "brightness_low",
      "mediaPlayPause": "play_pause",
      "mediaNext": "skip_next",
      "mediaPrevious": "skip_previous",
      "mediaStop": "stop",
      "terminal": "terminal",
      "fileManager": "folder",
      "browser": "language",
      "screenshot": "screenshot_region",
      "screenRecord": "videocam",
      "exitSession": "logout",
      "exec": "code",
      "raw": "data_object"
    })

  // [{ action, label, section, icon }], one per action, in schema order
  // The actions the running compositor can do (BindActions.needs); a saved
  // bind with another keeps it, flagged in `issues`
  readonly property var actionInfo: root.actions.filter(action => BindActions.supported(action, CompositorManager.supports)).map(action => ({
        "action": action,
        "label": root.actionLabels[action] ?? action,
        "section": action === "exec" ? "Apps" : BindActions.sectionFor(action),
        "icon": root._actionIcons[action] ?? "keyboard"
      }))

  function actionIcon(action) {
    return root._actionIcons[action] ?? "keyboard";
  }

  // What an action's free-text argument is, for its placeholder
  function argumentKind(action) {
    return BindActions.argumentKind(action);
  }

  function needsArgument(action) {
    return BindActions.needsArgument(action);
  }

  // How many workspaces a number can name: the layout's, or ten where the
  // compositor makes them itself (CompositorManager.dynamicWorkspaces)
  readonly property int workspaceKeys: CompositorManager.dynamicWorkspaces ? 10 : WorkspacesConfig.size

  // The choices for an action's argument, or null for free text
  function argumentOptions(action) {
    switch (BindActions.argumentKind(action)) {
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
    case "view":
      return OverlayConfig.views.filter(view => view.visible !== false).map(view => view.name || view.type).concat(["Layouts"]).filter((name, i, all) => all.indexOf(name) === i);
    }
    return null;
  }

  // The choices for an action's call, or null when it has none
  function callOptions(action) {
    return BindActions.hasCalls(action) ? ["toggle", "open", "close"] : null;
  }

  // A call's label for an action (a caffeine or night light bind turns it
  // on or off, a recording bind starts or stops it)
  function callLabels(action) {
    const onOff = action === "idleInhibit" || action === "nightLight";
    const record = action === "screenRecord";
    return {
      "toggle": I18n.tr("Toggle"),
      "open": record ? I18n.tr("Start") : onOff ? I18n.tr("Turn on") : I18n.tr("Open"),
      "close": record ? I18n.tr("Stop") : onOff ? I18n.tr("Turn off") : I18n.tr("Close")
    };
  }

  // Keys the compositor binds outside axiom, by BindKeys.keyId: every bind
  // it reports, less the saved axiom binds the layer applied
  readonly property var userKeyCounts: BindKeys.userKeyCounts(root._entries, root._appliedBinds)

  // The saved axiom binds the runtime layer applied (the rest it skipped)
  readonly property var _appliedBinds: {
    const skipped = CompositorConfigManager.skippedKeys.map(key => BindKeys.keyId(key));
    return KeybindsConfig.activeBinds.filter(bind => CompositorConfigManager.isComplete(bind) && !skipped.includes(BindKeys.keyId(bind.key)));
  }

  // Their keys, by BindKeys.keyId: { "64:return": bind }
  readonly property var _axiomIds: root._appliedBinds.reduce((ids, bind) => {
    const id = BindKeys.keyId(bind.key);
    if (id !== "")
      ids[id] = bind;
    return ids;
  }, {})

  // The saved axiom binds skipped because the user's config holds their
  // key, their labels by key: { "64:q": "Close window" }
  readonly property var _skippedLabels: {
    const skipped = CompositorConfigManager.skippedKeys.map(key => BindKeys.keyId(key));
    return KeybindsConfig.activeBinds.reduce((labels, bind) => {
      const id = BindKeys.keyId(bind.key);
      if (id !== "" && skipped.includes(id) && labels[id] === undefined)
        labels[id] = root.bindLabel(bind);
      return labels;
    }, {});
  }

  // A bind's label: its own (less a "Section:" prefix), else its action's
  function bindLabel(bind) {
    const own = String(bind?.description ?? "").trim();
    if (own !== "")
      return BindActions.hasOwnSection(own) ? own.slice(own.indexOf(":") + 1).trim() : own;
    return BindActions.defaultLabel(bind) || (root.actionLabels[bind?.action] ?? "");
  }

  // The modifiers' names, in the order a combo shows them
  readonly property var modifierNames: root._modifiers.map(m => m.name)
  readonly property var _modifiers: [
    {
      name: "SUPER",
      mask: 64
    },
    {
      name: "CTRL",
      mask: 4
    },
    {
      name: "ALT",
      mask: 8
    },
    {
      name: "SHIFT",
      mask: 1
    },
    {
      name: "MOD2",
      mask: 16
    },
    {
      name: "MOD3",
      mask: 32
    },
    {
      name: "MOD5",
      mask: 128
    },
    {
      name: "CAPS",
      mask: 2
    },
  ]

  readonly property var _keyNames: ({
      "mouse:272": "LMB",
      "mouse:273": "RMB",
      "mouse:274": "MMB",
      "mouse_up": "Scroll ↑",
      "mouse_down": "Scroll ↓",
      "mouse_left": "Scroll ←",
      "mouse_right": "Scroll →",
      "super_l": "Super L",
      "super_r": "Super R",
      "control_l": "Ctrl L",
      "control_r": "Ctrl R",
      "alt_l": "Alt L",
      "alt_r": "Alt R",
      "shift_l": "Shift L",
      "shift_r": "Shift R",
      "left": "←",
      "right": "→",
      "up": "↑",
      "down": "↓"
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
      const description = (entry.description || "").trim();
      const split = description.indexOf(": ");
      let title;
      let label;

      if (!description) {
        title = null;
        label = "";
      } else if (split > 0) {
        title = description.slice(0, split).trim();
        label = description.slice(split + 2).trim();
      } else {
        title = entry.submap || "";
        label = description;
      }

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

      const mods = root.decodeMods(entry.modmask);
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

  function decodeMods(modmask) {
    return root._modifiers.filter(m => (modmask & m.mask) !== 0).map(m => m.name);
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
  Component.onCompleted: refresh()
}
