pragma Singleton
import Quickshell
import qs.components.methods

// App and window icons as sources the icon theme holds: IconResolver's
// guesses (pure, tested), given the theme and the desktop entries.
Singleton {
  id: root

  readonly property var _lookup: ({
      "entry": windowClass => DesktopEntries.heuristicLookup(windowClass),
      "exists": name => Quickshell.iconPath(name, true).length > 0,
      "apps": () => DesktopEntries.applications.values
    })

  // An icon's source if the theme has it, else the generic program icon's,
  // else "": an Image given a name the theme lacks logs `Could not load icon`
  function appIcon(name) {
    return (name ? Quickshell.iconPath(name, true) : "") || Quickshell.iconPath("application-x-executable", true);
  }

  function resolveWindowIcon(windowClass, windowTitle) {
    const baseIcon = appIcon(IconResolver.guessIcon(windowClass, root._lookup));
    // Special case for kitty running nvim
    if (baseIcon.includes("kitty") && windowTitle?.toLowerCase().includes("nvim"))
      return appIcon("nvim");
    return baseIcon;
  }
}
