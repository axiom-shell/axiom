pragma Singleton
import QtQuick

// The screen-share picker's pure parts: which portal backend a compositor
// shares through and the line that points it at axiom (the hookup), the
// request's windows matched to the compositor's (for icons and previews),
// and the first selection.
// No file access, processes or services: the caller passes the request,
// windows and outputs.
QtObject {
  id: root

  // The portal backend each compositor shares through: its package, its
  // .portal file (in xdg-desktop-portal/portals/: installed), its D-Bus name
  // (busName, the owner of which the daemon restarts, in this session only,
  // for a hookup to take) and the user services to restart besides
  // xdg-desktop-portal. Under niri, axiom's own backend (axiom.portal)
  // shares, GNOME's answering with axiom's picker off
  readonly property var portals: ({
      "hyprland": {
        "package": "xdg-desktop-portal-hyprland",
        "portalFile": "hyprland.portal",
        "busName": "org.freedesktop.impl.portal.desktop.hyprland",
        "services": ["xdg-desktop-portal-hyprland"]
      },
      "sway": {
        "package": "xdg-desktop-portal-wlr",
        "portalFile": "wlr.portal",
        "busName": "org.freedesktop.impl.portal.desktop.wlr",
        "services": ["xdg-desktop-portal-wlr"]
      },
      "niri": {
        "package": "xdg-desktop-portal-gnome",
        "portalFile": "gnome.portal",
        "busName": "org.freedesktop.impl.portal.desktop.gnome",
        "axiomPortalFile": "axiom.portal",
        "services": []
      }
    })

  // The portal backend `kind` shares through (null for none known)
  function portal(kind) {
    return root.portals[kind] ?? null;
  }

  // The hookup targets that point `kind`'s portal at axiom's picker, the
  // binary at `bin`. xdph runs its picker binary with no arguments (axiom
  // knows it by xdph's environment); xdpw runs its chooser through sh;
  // niri has none: the daemon adds its portal line itself while axiom runs
  // (screenshare.portalLine).
  function hookupTargets(kind, bin) {
    switch (kind) {
    case "hyprland":
      return [
        {
          "title": "xdg-desktop-portal-hyprland",
          "file": "{config}/hypr/xdph.conf",
          "place": "end",
          "text": `screencopy:custom_picker_binary = ${bin}`,
          "note": "Adds the line at the end: Hyprland's portal runs axiom as its share picker."
        }
      ];
    case "sway":
      return [
        {
          "title": "xdg-desktop-portal-wlr",
          "file": "{config}/xdg-desktop-portal-wlr/config",
          "place": "section",
          "section": "screencast",
          "text": `chooser_type = dmenu\nchooser_cmd = '${bin}' screenshare-pick --for xdpw`,
          "note": "Sets the [screencast] chooser: wlroots' portal asks axiom what to share."
        }
      ];
    }
    return [];
  }

  // The request's windows, each with `match`: the compositor window it is
  // (from `windows`, CompositorManager's), or null. By id when the
  // backend gave one, else by title (and app, when both say)
  function windowTiles(request, windows) {
    return (request?.windows ?? []).map(w => {
      let match = null;
      if (w.id)
        match = windows.find(c => String(c.id) === String(w.id)) ?? null;
      if (!match && w.title) {
        const same = windows.filter(c => c.title === w.title && (!w.appId || !c.appId || c.appId === w.appId));
        if (same.length === 1)
          match = same[0];
      }
      return {
        "token": w.token,
        "title": w.title || match?.title || "",
        "appId": w.appId || match?.appId || "",
        "match": match
      };
    });
  }

  // What's selected when the picker opens: the focused output when it's
  // offered, else the first screen, else the first window
  function initialChoice(request, focusedOutput) {
    const outputs = request?.outputs ?? [];
    const out = outputs.find(o => o.name === focusedOutput) ?? outputs[0];
    if (out)
      return {
        "kind": "screen",
        "output": out.name
      };
    const win = (request?.windows ?? [])[0];
    if (win)
      return {
        "kind": "window",
        "window": win.token
      };
    return null;
  }
}
