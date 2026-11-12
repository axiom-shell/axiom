pragma Singleton
import QtQuick

// A keybind's "Only when" (the schema's Keybinds.binds[].whenCompositors,
// whenLayout, whenMonitors): whether it holds for the setup now, which
// binds can never be bound together, and what's missing. The daemon's
// render.BindHolds is the same rule (shared fixtures). `facts` is
// { kind, strips, grid, dynamic, outputs }: the compositor's kind, whether
// any output is a strip, the grid layout, dynamic workspaces, and the
// connected outputs' names (null until known).
QtObject {
  id: root

  // Connector names of a laptop's own panel
  readonly property var _internal: /^(eDP|LVDS|DSI)-/

  // Pairs of layouts that can't hold together: dynamic workspaces are a
  // strip per output (niri, or Hyprland's scrolling layout), never the grid
  readonly property var _exclusiveLayouts: [["strips", "tiling"], ["tiling", "dynamic"], ["grid", "dynamic"]]

  // The layouts a bind needs: its own, and strips for a strip action
  function layoutsOf(bind) {
    const out = [];
    const own = bind?.whenLayout ?? "";
    if (own !== "")
      out.push(own);
    if (String(bind?.action ?? "").startsWith("strip") && own !== "strips")
      out.push("strips");
    return out;
  }

  // The compositors a bind is for ([] for any): a raw command's own
  function compositorsOf(bind) {
    return bind?.action === "raw" ? [bind?.compositor ?? "hyprland"] : (bind?.whenCompositors ?? []);
  }

  function _layoutHolds(layout, facts) {
    switch (layout) {
    case "strips":
      return facts?.strips === true;
    case "tiling":
      return facts?.strips !== true;
    case "grid":
      return facts?.grid === true;
    case "dynamic":
      return facts?.dynamic === true;
    }
    return false;
  }

  function _monitorsHold(monitors, outputs) {
    if (!Array.isArray(outputs) || outputs.length === 0)
      return false;
    const internal = outputs.filter(name => root._internal.test(String(name))).length;
    return monitors === "external" ? internal < outputs.length : internal === outputs.length;
  }

  // The first part of a bind's condition that doesn't hold: "compositor",
  // a layout ("strips", "tiling", "grid", "dynamic") or monitors
  // ("external", "laptopOnly"); "" when it holds. A raw command's own
  // compositor is BindActions.appliesUnder's, not this: a raw bind's
  // whenCompositors (hidden in the editor) is ignored.
  function unmet(bind, facts) {
    const compositors = bind?.action === "raw" ? [] : (bind?.whenCompositors ?? []);
    if (compositors.length > 0 && !compositors.includes(facts?.kind))
      return "compositor";
    for (const layout of root.layoutsOf(bind))
      if (!root._layoutHolds(layout, facts))
        return layout;
    const monitors = bind?.whenMonitors ?? "";
    if (monitors !== "" && !root._monitorsHold(monitors, facts?.outputs))
      return monitors;
    return "";
  }

  // Whether a bind's condition holds, so it's bound
  function holds(bind, facts) {
    return root.unmet(bind, facts) === "";
  }

  // Whether a bind has a condition of its own
  function conditional(bind) {
    return (bind?.whenCompositors ?? []).length > 0 || (bind?.whenLayout ?? "") !== "" || (bind?.whenMonitors ?? "") !== "";
  }

  // Whether two binds can never be bound at once (so one key may hold
  // both): no compositor in common, layouts that exclude each other, or
  // other monitors
  function exclusive(a, b) {
    const ca = root.compositorsOf(a);
    const cb = root.compositorsOf(b);
    if (ca.length > 0 && cb.length > 0 && !ca.some(kind => cb.includes(kind)))
      return true;
    const la = root.layoutsOf(a);
    const lb = root.layoutsOf(b);
    if (root._exclusiveLayouts.some(pair => (la.includes(pair[0]) && lb.includes(pair[1])) || (la.includes(pair[1]) && lb.includes(pair[0]))))
      return true;
    const ma = a?.whenMonitors ?? "";
    const mb = b?.whenMonitors ?? "";
    return ma !== "" && mb !== "" && ma !== mb;
  }
}
