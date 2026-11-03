pragma Singleton
import QtQuick

// Whether a window belongs to a notification's app, for NotificationManager
// (clicks focusing the app, clear on focus, per-app rules). Apps name
// themselves differently in each place: a window class `dev.vencord.Vesktop`
// with app name `Vesktop`, `org.telegram.desktop` with `Telegram`, a desktop
// entry `signal-desktop` with the class `signal`. Each name is reduced to
// keys and two sides match when they share one.
QtObject {
  id: root

  // A name lowercased, without a `.desktop` suffix, spaces and underscores
  // as dashes: "Google Chrome" -> "google-chrome"; "" for none
  function normalize(name) {
    return String(name ?? "").trim().toLowerCase().replace(/\.desktop$/, "").replace(/[\s_]+/g, "-");
  }

  // The keys of some names (a desktop entry, an app name, a window class,
  // a StartupWMClass): each normalized, its last part when reverse-DNS
  // ("dev.vencord.vesktop" -> "vesktop", unless that part is a generic one
  // like "desktop" or "app"), and without a "-desktop" or "-bin" suffix
  function keys(names) {
    const out = [];
    const add = k => {
      if (k && !out.includes(k))
        out.push(k);
    };
    for (const name of names ?? []) {
      const n = root.normalize(name);
      if (!n)
        continue;
      add(n);
      const parts = n.split(".");
      if (parts.length > 1) {
        const last = parts[parts.length - 1];
        add(root._generic.includes(last) ? parts[parts.length - 2] : last);
      }
      add(n.replace(/-(desktop|bin)$/, ""));
    }
    return out;
  }

  // Whether two sets of keys (from keys()) share one
  function matches(a, b) {
    return (a ?? []).some(k => (b ?? []).includes(k));
  }

  readonly property var _generic: ["desktop", "app", "client", "application"]
}
