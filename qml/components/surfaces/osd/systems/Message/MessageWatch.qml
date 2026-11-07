pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ui
import qs.components.surfaces.osd.engine

// Messages' state for the OSD: each message ShellManager.osdMessage sends
// to this OSD (OSDConfig.messageOsd picks it), pulsed so the same text
// twice shows twice. It starts with none, so the first one counts
OSDWatch {
  id: root

  state: ({
      "message": {
        "event": root.events.message?.event ?? null,
        "seq": root.events.message?.seq ?? 0
      }
    })

  Connections {
    target: ShellManager
    function onOsdMessage(id, icon, text, detail, tone) {
      if (id === root.osdId)
        root.pulse("message", {
          "icon": icon,
          "text": text,
          "detail": detail,
          "tone": tone
        });
    }
  }
}
