pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// The VPNs' state for the OSD: each row's state by its id (its definition
// judges them by the state they last settled in), the first one up's
// address. Held, so Tailscale is listed (polled) while it is. Not
// available with no VPN (NetworkManager running isn't one)
OSDWatch {
  holds: [VpnManager]

  state: ({
      "vpn": {
        "available": VpnManager.rows.length > 0,
        "members": VpnManager.rows.map(r => ({
              "id": r.id,
              "name": r.name,
              "state": r.state
            })),
        "address": VpnManager.primary?.ipv4 ?? ""
      }
    })
}
