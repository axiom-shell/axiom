pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Messages on the OSD: what `axiom message`, ShellManager.confirm and
// ShellManager.refuse send to this OSD, only ever its card: its icon (the
// chat bubble for none), the text as the title, the detail as the faint
// line, shown as sent (the sender translates it); a refusal's picture on
// the warning colour (`tone`). Every one counts, the same text twice too.
// It shows beside whatever else is out and gives way within the quiet
// window only to another card (the default sameChange: it never comes
// without its card, and has no tile to ring)
OSDSystem {
  model: "event"
  onAdd: "card"

  // I18n.tr("Messages")
  exposes: [
    {
      "key": "message",
      "part": "card",
      "icon": "chat",
      "label": "Messages"
    }
  ]

  // state: { event ({ icon, text, detail, tone }), seq }
  function card(change, state) {
    const e = state.message?.event ?? null;
    if (!e)
      return null;
    return {
      "icon": e.icon || "chat",
      "title": e.text ?? "",
      "detail": e.detail ?? "",
      "tone": e.tone ?? ""
    };
  }
}
