pragma Singleton
import QtQuick

// What each keybind action (the schema's Keybinds.binds[].action) is, read
// off its table: the daemon's (compositor.bindActions, KeybindManager.
// actionTable; backend/internal/compositor/actions/table.json says what
// each part holds), handed in as `table`. How each compositor binds an
// action is the daemon's render (DispatcherLua, SwayActionCommand,
// NiriActionNode). Labels aren't translated: they go to the compositor,
// like the user's own bind descriptions.
QtObject {
  id: root

  // Whether the compositor (its `supports`) can run `action`
  function supported(table, action, supports) {
    const caps = table?.needs?.[action];
    return !caps || caps.some(cap => supports?.[cap] === true);
  }

  // Whether `bind` does anything under compositor `kind` with `supports`:
  // its action is supported, a raw command is written for `kind`, and a
  // modifier tapped on its own is a key the compositor can bind
  function appliesUnder(table, bind, kind, supports) {
    return root.supported(table, bind.action, supports) && (bind.action !== "raw" || (bind.compositor ?? "hyprland") === kind) && root.keySupported(bind.key, supports);
  }

  // Whether the compositor (its `supports`) can bind `key`: a tap
  // (KeyNames.tapModifier) needs modifierTap
  function keySupported(key, supports) {
    return KeyNames.tapModifier(key) === "" || supports?.modifierTap === true;
  }

  // The modifiers a switcher combo is held by (KeyNames.split's `mods`):
  // all but SHIFT, which only turns it around, unless SHIFT is all there is
  function switcherHeld(mods) {
    const held = (mods ?? []).filter(mod => mod !== "SHIFT" && ["SUPER", "CTRL", "ALT"].includes(mod));
    return held.length > 0 || !(mods ?? []).includes("SHIFT") ? held : ["SHIFT"];
  }

  // Whether an action takes a call (toggle, open or close)
  function hasCalls(table, action) {
    return table?.calls?.[action] !== undefined;
  }

  // A bind's call ({ action, call }): "toggle" unless its action has the
  // one it names
  function callOf(table, bind) {
    return table?.calls?.[bind.action]?.[bind.call] !== undefined ? bind.call : "toggle";
  }

  // The IPC function a bind's call runs ("toggle", or the action's own
  // name for open/close, e.g. "show")
  function callFunction(table, bind) {
    return table?.calls?.[bind.action]?.[root.callOf(table, bind)] ?? "toggle";
  }

  // The IPC call ({ target, function, args }) an axiom action (one of
  // ipcActions) makes with `argument` and `call` (toggle, open or close),
  // as its bind does; null for another action, or one missing its argument
  function ipcCall(table, action, argument, call) {
    const template = table?.ipcActions?.[action]?.[0];
    const text = String(argument ?? "").trim();
    if (!template || (template.includes("{0}") && text === ""))
      return null;
    const fn = root.callFunction(table, {
      "action": action,
      "call": call
    });
    const words = template.split(" ").map(word => word === "{call}" ? fn : word.replace("{0}", text));
    return {
      "target": words[0],
      "function": words[1],
      "args": words.slice(2)
    };
  }

  // What `action`'s argument is (argumentKinds), or ""
  function argumentKind(table, action) {
    return table?.argumentKinds?.[action] ?? "";
  }

  // Whether `action` needs an argument to be bound
  function needsArgument(table, action) {
    return table?.argumentKinds?.[action] !== undefined;
  }

  // The section a bind's action files it under on the Keybinds page
  function sectionFor(table, action) {
    return table?.ipcActions?.[action]?.[2] ?? table?.compositorActions?.[action]?.[1] ?? "Axiom";
  }

  // The label a bind ({ action, argument, call }) gets when its
  // description is empty: `exec` shows its command, a call other than
  // toggle is added in brackets
  function defaultLabel(table, bind) {
    const argument = String(bind.argument ?? "").trim();
    if (bind.action === "exec")
      return argument;
    const label = (table?.ipcActions?.[bind.action]?.[1] ?? table?.compositorActions?.[bind.action]?.[0] ?? "").replace("{0}", argument);
    const call = root.callOf(table, bind);
    return call === "toggle" ? label : `${label} (${call})`;
  }

  // Whether a description names its own section ("Section: Label")
  function hasOwnSection(description) {
    return /^[^:]+: \S/.test(String(description ?? "").trim());
  }

  // The description the compositor gets for a bind: "Section: Label", the
  // section from the action unless the description names its own
  function descriptionFor(table, bind) {
    const own = String(bind.description ?? "").trim();
    return root.hasOwnSection(own) ? own : root.sectionFor(table, bind.action) + ": " + (own || root.defaultLabel(table, bind));
  }
}
