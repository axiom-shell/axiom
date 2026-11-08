pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// VPNs on the OSD: one tile, lit and unusual while one is up (the VPNs up
// name it). One coming up is its card (their names, Connected, the first
// one's address); one taken down on screen is the unlit icon; the last
// one going down that nobody took down on screen is a "Disconnected"
// card. Every change counts, the user's or not (a drop, an autoconnect);
// up and down are judged across connecting and disconnecting, and a row
// appearing (Tailscale's first status) or going away is neither. Its card
// folds back as the VPNs go down. VpnWatch reads VpnManager; nothing is
// judged with no VPN
OSDSystem {
  model: "set"
  // Each VPN by its row's settled state
  memberState: ({
      "field": "state",
      "on": "on",
      "off": "off"
    })
  onAdd: "card"
  onRemove: "icon"
  // Unexpected: the Disconnected card, but the icon while another is
  // still up (the other half of a switch)
  onUnexpectedRemove: "last"
  anyone: true
  retractsCardWhenOff: true
  // A connection's state settles seconds after the click
  userWindow: 15000

  // I18n.tr("VPN")
  exposes: [
    {
      "key": "vpn",
      "part": "tile",
      "icon": "vpn_key",
      "label": "VPN",
      "action": "vpn"
    }
  ]

  // state: { available (any VPN known), members: [{ id, name, state ("on"
  // | "off" | "connecting" | "disconnecting") }], address (the first one
  // up's IPv4) }
  function tile(key, state) {
    const up = (state?.members ?? []).filter(m => m.state === "on");
    const on = up.length > 0;
    return {
      "name": up.map(m => m.name).join(", "),
      "address": on ? (state?.address ?? "") : "",
      "on": on,
      "notable": on,
      "hidden": state?.available !== true
    };
  }

  // Up: the VPNs up now, Connected, the first one's address; a drop: the
  // ones that went down, Disconnected
  // I18n.tr("Connected") I18n.tr("Disconnected")
  function card(change, state) {
    if (change.kind === "remove")
      return {
        "icon": "vpn_key_off",
        "title": (change.members ?? []).filter(m => (change.removed ?? []).includes(m.id)).map(m => m.name).join(", "),
        "role": "Disconnected"
      };
    const t = tile("vpn", state.vpn);
    return {
      "title": t.name,
      "role": "Connected",
      "detail": t.address
    };
  }
}
