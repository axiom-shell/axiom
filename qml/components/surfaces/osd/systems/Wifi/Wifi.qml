pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Wi-Fi on the OSD: the radio's tile (unusual while off; the network
// joined names it) and a network joined, its card (its name, Connected
// and its signal, filling in as the scanned list catches up). Leaving a
// network shows nothing; another one is reached through disconnected, so
// it's a card too. Its card folds back as Wi-Fi turns off, and Wi-Fi
// switching just after airplane mode is its knock-on. WifiWatch reads
// NetworkingManager; nothing is judged with no Wi-Fi device
OSDSystem {
  // Joined: its card; left: nothing; the radio on or off: its icon (off
  // while joined is both, and the icon shows)
  onAdd: "card"
  onRemove: "none"
  retractsCardWhenOff: true
  knockOnOf: ["Airplane"]
  // A connection's state settles seconds after the click
  userWindow: 8000

  // I18n.tr("Wi-Fi")
  exposes: [
    {
      "key": "wifi",
      "part": "tile",
      "icon": "wifi",
      "label": "Wi-Fi",
      "action": "wifi"
    }
  ]

  // state: { available, on (the radio), value (joined), network (its
  // name, "" until the list catches up), signal (0-100) }; the network
  // names it only while on and joined
  function tile(key, state) {
    const on = state?.on === true;
    const joined = on && state?.value === true && !!state?.network;
    return Object.assign({
      "on": on,
      "notable": !on,
      "hidden": state?.available === false
    }, joined ? {
      "name": state.network,
      "signal": state.signal ?? 0
    } : {});
  }

  // A network joined: its name, Connected, its signal once it's named
  // I18n.tr("Connected")
  function card(change, state) {
    if (change.kind !== "add")
      return null;
    const t = tile("wifi", state.wifi);
    return {
      "title": t.name ?? "",
      "role": "Connected",
      "detail": t.name ? `${t.signal}%` : ""
    };
  }
}
