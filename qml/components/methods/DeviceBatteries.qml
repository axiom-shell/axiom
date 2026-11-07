pragma Singleton
import QtQuick

// When a Bluetooth device's battery is said to be low (BluetoothManager):
// each connected device that reports one, once per drop to low and then
// to critical, never for what's there at the start or after a resync, and
// again once its level recovers or it connects again.
QtObject {
  id: root

  // "critical" at or below `critical`, "low" at or below `low`, else
  // "none" (`percent` 0-100)
  function level(percent, low, critical) {
    if (percent <= critical)
      return "critical";
    if (percent <= low)
      return "low";
    return "none";
  }

  // One state's step, from `last` (each device's level as last judged,
  // `{ address: "none" | "low" | "critical" }`, what this returned before;
  // null at the start or after a resync: what's there is taken as it is,
  // never said) and `devices` (`[{ address, connected, battery }]`,
  // battery 0-100 or -1 for none). { last, drops: [{ address, level }] }:
  // a device connected and reporting its battery whose level fell (from
  // none to low or critical, from low to critical) since it was last
  // judged, or, newly connected (or its battery newly reported), already
  // low. A device disconnected or without a battery is forgotten, so it's
  // judged anew when it's back
  function step(last, devices, low, critical) {
    const next = {};
    const drops = [];
    for (const d of devices ?? []) {
      if (!d.connected || !(d.battery >= 0))
        continue;
      const now = root.level(d.battery, low, critical);
      next[d.address] = now;
      if (!last)
        continue;
      const was = last[d.address] ?? "none";
      if ((now === "critical" && was !== "critical") || (now === "low" && was === "none"))
        drops.push({
          "address": d.address,
          "level": now
        });
    }
    return {
      "last": next,
      "drops": drops
    };
  }
}
