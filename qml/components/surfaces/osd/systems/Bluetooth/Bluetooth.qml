pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Bluetooth on the OSD: the radio's tile (never unusual; the connected
// devices name it) and its devices' card: connecting, disconnecting, a
// device's battery low or critical (an alert: it opens the OSD even just
// after a click). One key holds both, so the card folds back as the radio
// turns off, and the radio coming on under it is its own knock-on. A
// headset's card takes in Audio switching to it and its level arriving
// late (absorbs). BluetoothWatch
// reads BluetoothManager; nothing is judged with no adapter
OSDSystem {
  // The radio on or off: its icon; a new event of its devices: its card
  carriesEvents: true
  alertKinds: ["low", "critical"]
  retractsCardWhenOff: true
  knockOnOf: ["Airplane"]
  // A connection's state settles seconds after the click
  userWindow: 8000

  // I18n.tr("Bluetooth")
  exposes: [
    {
      "key": "bluetooth",
      "part": "tile",
      "icon": "bluetooth",
      "label": "Bluetooth",
      "action": "bluetooth"
    }
  ]

  // state: { available, value (the radio on), connected (the connected
  // devices' names), event (BluetoothManager.lastEvent: { kind:
  // "connected" | "disconnected" | "low" | "critical", devices: [{
  // address, name, glyph, battery (0-100, -1 none) }] }, or null), seq };
  // the tile carries the last event's kind and devices (absorbs reads
  // them)
  function tile(key, state) {
    const on = state?.value === true;
    const e = state?.event ?? null;
    return {
      "name": on ? (state?.connected ?? []).join(", ") : "",
      "event": e?.kind ?? "",
      "devices": e?.devices ?? [],
      "on": on,
      "hidden": state?.available === false
    };
  }

  // Its devices' last event: one device's own icon and battery, several
  // their names under Bluetooth's icon; a battery low or critical its
  // level, critical on the warning colour. The radio has none
  // I18n.tr("Connected") I18n.tr("Disconnected") I18n.tr("Battery low") I18n.tr("Battery critically low")
  function card(change, state) {
    if (change.kind !== "event")
      return null;
    const t = tile("bluetooth", state.bluetooth);
    const devices = t.devices;
    const one = devices.length === 1 ? devices[0] : null;
    const battery = one && one.battery >= 0 ? `${one.battery}%` : "";
    const out = {
      "title": devices.map(d => d.name).join(", ")
    };
    switch (t.event) {
    case "low":
    case "critical":
      {
        const critical = t.event === "critical";
        return Object.assign(out, {
          "icon": critical ? "battery_alert" : "battery_low",
          "role": critical ? "Battery critically low" : "Battery low",
          "detail": battery,
          "tone": critical ? "warning" : ""
        });
      }
    case "disconnected":
      return Object.assign(out, {
        "icon": "bluetooth_disabled",
        "role": "Disconnected"
      });
    }
    return Object.assign(out, {
      "icon": one?.glyph || "bluetooth",
      "role": "Connected",
      "detail": battery
    });
  }

  // Its devices' "connected" card takes in Audio switching the output or
  // input to one of them (its Bluetooth address, in any case), and that
  // device's level arriving late (a bar's tile is its device's:
  // OSDEngine.contextTile): a headset connecting is one change. A switch
  // or a level, never a mute
  function absorbs(own, other) {
    const address = String(other.tile?.address ?? "").toUpperCase();
    if (other.system !== "Audio" || (other.card !== true && other.part !== "bar") || address === "" || own.tile?.event !== "connected")
      return false;
    return (own.tile.devices ?? []).some(d => String(d.address).toUpperCase() === address);
  }
}
