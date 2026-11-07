.pragma library
// Timelines across systems: the host's arbitration (OSDEngine.arbitrate)
// between one system's change and another's
var rows = [
  {
    "name": "an unrelated toggle shows beside a card out",
    "systems": ["Caffeine"],
    "host": { "card": { "system": "Vpn", "key": "vpn", "at": 0 } },
    "steps": [
      { "system": "Caffeine", "at": 0, "state": { "caffeine": { "value": false } } },
      { "system": "Caffeine", "at": 300, "state": { "caffeine": { "value": true } },
        "expect": { "show": "tile", "host": "beside" } }
    ]
  },
  {
    "name": "airplane mode's knock-on keeps the ring",
    "systems": ["Airplane", "Wifi"],
    "steps": [
      { "system": "Airplane", "at": 0, "state": { "airplane": { "value": false } } },
      { "system": "Wifi", "at": 0, "state": { "wifi": { "value": "", "on": true } } },
      { "system": "Airplane", "at": 3000, "state": { "airplane": { "value": true } },
        "expect": { "show": "tile", "host": "ring" } },
      { "system": "Wifi", "at": 3300, "state": { "wifi": { "value": "", "on": false } },
        "expect": { "show": "tile", "host": "keep" } }
    ]
  }
];
