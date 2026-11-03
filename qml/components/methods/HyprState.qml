pragma Singleton
import QtQuick

// Hyprland's JSON replies (HyprlandManager) as the shapes the rest of the
// shell reads, which don't depend on the compositor: what another
// compositor's service would hand back too.
QtObject {
  id: root

  // The main keyboard's layouts from a j/devices reply: { layouts: ["us",
  // "de"], index (the active one's), keymap (its name) }, or null with no
  // keyboard
  function keyboard(devices) {
    const keyboards = devices?.keyboards ?? [];
    const main = keyboards.find(k => k.main) ?? keyboards[0];
    if (!main)
      return null;
    return {
      "layouts": String(main.layout ?? "").split(",").map(layout => layout.trim()).filter(layout => layout !== ""),
      "index": main.active_layout_index ?? 0,
      "keymap": main.active_keymap ?? ""
    };
  }

  // A client from j/clients as a window (docs/dev/compositor/contract.md),
  // or null while it isn't mapped. outputNames: { [monitor id]: name }, as
  // a client names its monitor by id. Fullscreen mode is a bitmask: 1 is
  // maximized, 2 fullscreen.
  function window(client, outputNames) {
    if (!client || client.mapped === false)
      return null;
    const mode = Number(client.fullscreen) || 0;
    return {
      "id": String(client.address ?? ""),
      "appId": client["class"] ?? "",
      "initialAppId": client.initialClass ?? "",
      "title": client.title ?? "",
      "workspaceId": client.workspace?.id ?? -1,
      "workspaceName": client.workspace?.name ?? "",
      "output": outputNames?.[client.monitor] ?? "",
      "floating": client.floating === true,
      "fullscreen": (mode & 2) !== 0,
      "maximized": (mode & 1) !== 0,
      "hidden": client.hidden === true,
      "focusRank": client.focusHistoryID,
      "x": client.at?.[0] ?? 0,
      "y": client.at?.[1] ?? 0,
      "w": client.size?.[0] ?? 0,
      "h": client.size?.[1] ?? 0
    };
  }

  // A monitor (Quickshell's HyprlandMonitor, or its fields) as an output.
  // Its lastIpcObject carries the special workspace, the transform and the
  // reserved space ([left, top, right, bottom], a QVariantList that isn't a
  // JS Array, so it's read by index).
  function output(monitor, focused) {
    const ipc = monitor?.lastIpcObject ?? {};
    const scale = monitor?.scale || 1;
    const turned = (ipc.transform ?? 0) % 2 === 1;
    const reserved = ipc.reserved?.length === 4 ? [0, 1, 2, 3].map(i => Number(ipc.reserved[i]) || 0) : [0, 0, 0, 0];
    return {
      "name": monitor?.name ?? "",
      "description": monitor?.description ?? "",
      "x": monitor?.x ?? 0,
      "y": monitor?.y ?? 0,
      "width": (turned ? monitor?.height : monitor?.width) / scale || 0,
      "height": (turned ? monitor?.width : monitor?.height) / scale || 0,
      "scale": scale,
      "focused": focused === true,
      "activeWorkspaceId": monitor?.activeWorkspace?.id ?? -1,
      "specialWorkspaceId": ipc.specialWorkspace?.id ?? 0,
      "reserved": {
        "left": reserved[0],
        "top": reserved[1],
        "right": reserved[2],
        "bottom": reserved[3]
      }
    };
  }

  // A workspace (Quickshell's HyprlandWorkspace, or its fields)
  function workspace(ws) {
    return {
      "id": ws?.id ?? -1,
      "name": ws?.name ?? "",
      "output": ws?.monitor?.name ?? "",
      "windowCount": ws?.toplevels?.values?.length ?? 0,
      "active": ws?.active === true,
      "focused": ws?.focused === true
    };
  }

  // Each monitor's logical size and the layer surfaces on it, from j/monitors
  // and j/layers: { [monitor name]: { w, h, layers: [{ namespace, x, y, w,
  // h }] } }, layer positions relative to the monitor, all in logical px
  function layerRects(monitors, layers) {
    const result = {};
    for (const monitor of monitors ?? []) {
      const levels = layers?.[monitor.name]?.levels ?? {};
      // Layer geometry is in logical px, as the monitor's size isn't
      const scale = monitor.scale || 1;
      const turned = monitor.transform % 2 === 1;
      result[monitor.name] = {
        "w": (turned ? monitor.height : monitor.width) / scale,
        "h": (turned ? monitor.width : monitor.height) / scale,
        "layers": [].concat(...Object.keys(levels).map(level => levels[level])).map(l => ({
              "namespace": l.namespace,
              "x": l.x - monitor.x,
              "y": l.y - monitor.y,
              "w": l.w,
              "h": l.h
            }))
      };
    }
    return result;
  }
}
