.pragma library
// Vpn's timelines: whether a VPN is up. One coming up is its card (its
// name, Connected, its address); one taken down on screen is the unlit
// icon; one going down that nobody took down on screen is a "Disconnected"
// card (new). Every change counts, the user's or not (a drop, an
// autoconnect); up and down are judged across connecting / disconnecting,
// and a row appearing (Tailscale's first status) or going away isn't one.
// Its card folds back as the VPNs turn off.
//
// State by key (VpnWatch; VpnManager.rows, acquired, so Tailscale is
// polled while held):
//   vpn  { available (VpnManager.rows.length > 0), members: [{ id, name,
//        state ("on" | "off" | "connecting" | "disconnecting") }] (every
//        row, as it is now), address (the first one up's IPv4) }
//
// decided: declared, no judge(): model "set" with `memberState: { field:
//   "state", on: "on", off: "off" }`: the set is the VPNs up; one up
//   that was known before (settled "on" or "off") is "add" (its card),
//   one down that is still known is "remove"; a row in transit is judged as it last settled (remember keeps
//   that reading), one appearing or going away is neither. With both in
//   one reading (a switch) it's the add.
// decided: the drop's card is `onUnexpectedRemove: "last"` (a card for the
//   last one going, the icon while another is up).
// decided: a VPN down that wasn't marked on screen (`unexpected`) is the
//   "Disconnected" card (title its name, icon "vpn_key_off"), unless another
//   VPN is still up (`left` not empty): that's the other half of a switch,
//   the icon (suppressed under the switch's card). A keybind or IPC taking
//   one down isn't marked, so it gets the card too (accepted by the brief).
// decided: the card's `icon` for a drop is "vpn_key_off" (a card's icon
//   isn't held to the tiles' base icon, as Drives' "usb_off" isn't).

function v(id, name, on, state) {
  return { "id": id, "name": name, "state": state || (on ? "on" : "off") };
}
function vpn(members, address) {
  return { "available": true, "members": members, "address": address || "" };
}

var rows = [
  {
    "name": "no VPN: its tile hidden",
    "steps": [
      { "at": 0, "state": { "vpn": { "available": false, "members": [], "address": "" } },
        "tiles": { "vpn": { "hidden": true } } }
    ]
  },
  {
    "name": "the first reading shows nothing, one already up",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") } }
    ]
  },
  {
    "name": "one coming up: its card, its name, Connected and its address",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "kind": "add", "added": ["home"], "action": { "id": "vpn", "call": "toggle" },
          "tile": { "icon": "vpn_key", "on": true, "notable": true, "hidden": false, "slash": false, "name": "Home" },
          "card": { "icon": "vpn_key", "title": "Home", "role": "Connected", "detail": "10.0.0.2", "clickable": false },
          "host": "open" } }
    ]
  },
  {
    "name": "up through connecting: nothing on the way, the card once up",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false, "connecting")]) } },
      { "at": 4500, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "kind": "add" } }
    ]
  },
  {
    "name": "connecting then giving up: nothing",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false, "connecting")]) } },
      { "at": 9000, "state": { "vpn": vpn([v("home", "Home", false)]) } }
    ]
  },
  {
    "name": "brought up from the Vpn widget: still its card, the user's",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "byUser": true, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "byUser": true } }
    ]
  },
  {
    "name": "an autoconnect (nobody's): its card",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("ts", "Tailnet", false)]) } },
      { "at": 3000, "settled": false, "state": { "vpn": vpn([v("ts", "Tailnet", true)], "100.64.0.1") },
        "expect": { "key": "vpn", "show": "card", "card": { "title": "Tailnet", "detail": "100.64.0.1" } } }
    ]
  },
  {
    "name": "taken down on screen: the unlit icon",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") } },
      { "at": 3000, "byUser": true, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "tile", "kind": "remove", "unexpected": false, "removed": ["home"],
          "tile": { "on": false, "notable": false }, "host": "ring" } }
    ]
  },
  {
    "name": "going down unexpectedly: a Disconnected card",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "card", "kind": "remove", "unexpected": true, "removed": ["home"], "left": [],
          "tile": { "on": false },
          "card": { "icon": "vpn_key_off", "title": "Home", "role": "Disconnected", "detail": "" },
          "host": "open" } }
    ]
  },
  {
    "name": "going down unexpectedly through disconnecting: the card once down",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true, "disconnecting")], "10.0.0.2") } },
      { "at": 3800, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "card", "kind": "remove", "unexpected": true } }
    ]
  },
  {
    "name": "a switch in one reading: shown as the one up",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", false)], "10.0.0.2") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false), v("work", "Work", true)], "10.8.0.5") },
        "expect": { "key": "vpn", "show": "card", "kind": "add", "added": ["work"], "card": { "title": "Work", "role": "Connected", "detail": "10.8.0.5" } } }
    ]
  },
  {
    "name": "a switch, the new one up first: the old one going down is its other half, suppressed",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", false)], "10.0.0.2") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "kind": "add", "host": "open" } },
      { "at": 3400, "state": { "vpn": vpn([v("home", "Home", false), v("work", "Work", true)], "10.8.0.5") },
        "expect": { "key": "vpn", "show": "tile", "kind": "remove", "left": ["work"], "host": "suppress" } }
    ]
  },
  {
    "name": "a switch, the old one down first: its Disconnected card, then the new one's replaces it",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", false)], "10.0.0.2") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false), v("work", "Work", false)]) },
        "expect": { "key": "vpn", "show": "card", "card": { "role": "Disconnected" }, "host": "open" } },
      { "at": 3600, "state": { "vpn": vpn([v("home", "Home", false), v("work", "Work", true)], "10.8.0.5") },
        "expect": { "key": "vpn", "show": "card", "card": { "role": "Connected", "title": "Work" }, "host": "replace" } }
    ]
  },
  {
    "name": "taken down on screen just after its card: the card folds back, the icon shows",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "host": "open" } },
      { "at": 3300, "byUser": true, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "taken down on screen long after its card (still out): it folds back too",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "host": "open" } },
      { "at": 8000, "byUser": true, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "tile", "host": "retract" } }
    ]
  },
  {
    "name": "dropping just after its card: the Disconnected card replaces it",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "vpn": vpn([v("home", "Home", false)]) },
        "expect": { "key": "vpn", "show": "card", "card": { "role": "Disconnected" }, "host": "replace" } }
    ]
  },
  {
    "name": "another VPN up just after: its card replaces",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false), v("work", "Work", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", false)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "host": "open" } },
      { "at": 3300, "state": { "vpn": vpn([v("home", "Home", true), v("work", "Work", true)], "10.0.0.2") },
        "expect": { "key": "vpn", "show": "card", "card": { "title": "Home, Work" }, "host": "replace" } }
    ]
  },
  {
    "name": "a row appearing up (Tailscale's first status): nothing",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", true)], "100.64.0.1") } }
    ]
  },
  {
    "name": "a row going away while up: forgotten, nothing",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", true)], "100.64.0.1") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 6000, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", true)], "100.64.0.1") } }
    ]
  },
  {
    "name": "a row appearing connecting, then up: nothing (never known settled before)",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", false)]) } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", false, "connecting")]) } },
      { "at": 4000, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", true)], "100.64.0.1") } },
      { "at": 9000, "state": { "vpn": vpn([v("home", "Home", false), v("ts", "Tailnet", false)]) },
        "expect": { "key": "vpn", "show": "card", "kind": "remove", "card": { "title": "Tailnet", "role": "Disconnected" } } }
    ]
  },
  {
    "name": "the address filling in: nothing",
    "steps": [
      { "at": 0, "state": { "vpn": vpn([v("home", "Home", true)], "") } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", true)], "10.0.0.2") } }
    ]
  },
  {
    "name": "no VPN at all, then one appearing: nothing",
    "steps": [
      { "at": 0, "state": { "vpn": { "available": false, "members": [], "address": "" } } },
      { "at": 3000, "state": { "vpn": vpn([v("home", "Home", false)]) } }
    ]
  }
];
