pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Monitors on the OSD: a monitor connected or removed (MonitorManager's
// lastEvent, never one there at the start; read only where the
// compositor gives monitors, supports.monitors), only ever its card: its
// description (else its connector), Connected or Disconnected, and the
// connector and resolution
OSDSystem {
  model: "event"
  onAdd: "card"

  // I18n.tr("Monitors")
  exposes: [
    {
      "key": "monitor",
      "part": "card",
      "icon": "monitor",
      "label": "Monitors"
    }
  ]

  // state: { available (supports.monitors), event (MonitorManager's
  // lastEvent: { kind: "added" | "removed", name (the connector),
  // description, width, height }), seq }
  // I18n.tr("Connected") I18n.tr("Disconnected")
  function card(change, state) {
    const e = state.monitor?.event ?? null;
    if (!e)
      return null;
    const removed = e.kind === "removed";
    const size = (e.width ?? 0) > 0 ? `${e.width}×${e.height}` : "";
    return {
      "icon": removed ? "desktop_access_disabled" : "monitor",
      "title": e.description || e.name || "",
      "role": removed ? "Disconnected" : "Connected",
      "detail": [e.description ? (e.name ?? "") : "", size].filter(part => part !== "").join(" · ")
    };
  }
}
