pragma Singleton
import QtQuick
import Quickshell
import qs.components.methods

// App and window icons as sources the icon theme holds: IconResolver's
// guesses (pure, tested), given the theme and the desktop entries, worked
// out once per window class until the desktop entries change.
Singleton {
  id: root

  readonly property var _lookup: ({
      "entry": windowClass => DesktopEntries.heuristicLookup(windowClass),
      "exists": name => Quickshell.iconPath(name, true).length > 0,
      "apps": () => DesktopEntries.applications.values
    })

  // Window class -> its icon's source. A binding calling resolveWindowIcon
  // re-runs on every title change; the guess (up to a scan of every desktop
  // entry) runs once per class. Replaced, not mutated, when the entries
  // change, so the bindings reading it run again.
  property var _windowIcons: ({})

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root._windowIcons = {};
    }
  }

  // An icon's source if the theme has it, else the generic program icon's,
  // else "": an Image given a name the theme lacks logs `Could not load icon`
  function appIcon(name) {
    return (name ? Quickshell.iconPath(name, true) : "") || Quickshell.iconPath("application-x-executable", true);
  }

  function resolveWindowIcon(windowClass, windowTitle) {
    const key = windowClass ?? "";
    const icons = root._windowIcons;
    let baseIcon = icons[key];
    if (baseIcon === undefined) {
      baseIcon = appIcon(IconResolver.guessIcon(windowClass, root._lookup));
      icons[key] = baseIcon;
    }
    // Special case for kitty running nvim
    if (baseIcon.includes("kitty") && windowTitle?.toLowerCase().includes("nvim"))
      return appIcon("nvim");
    return baseIcon;
  }
}
