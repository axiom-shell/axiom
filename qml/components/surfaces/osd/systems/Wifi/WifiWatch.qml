pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Wi-Fi's state for the OSD: the radio on, the Wi-Fi device joined to a
// network (its own state, steadier than the scanned list, which can drop
// the network joined for a moment as it's rebuilt), the network's name
// and signal as the list has them. Not available with no Wi-Fi device
OSDWatch {
  state: {
    const joined = NetworkingManager.wifiDevice?.connected === true;
    return {
      "wifi": {
        "available": NetworkingManager.available,
        "on": NetworkingManager.wifiEnabled,
        "value": joined,
        "network": joined ? (NetworkingManager.activeNetwork?.name ?? "") : "",
        "signal": joined ? Math.round((NetworkingManager.activeNetwork?.signalStrength ?? 0) * 100) : 0
      }
    };
  }
}
