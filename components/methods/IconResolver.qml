pragma Singleton

import Quickshell

/**
 * Resolves icon names for window classes: desktop entries first, then known
 * substitutions, then name variants that exist in the icon theme. Turns an
 * app's icon name into a source only the theme holds (`appIcon`).
 * Substitution tables adapted from end-4's dots-hyprland.
 */
Singleton {
  id: root

  readonly property var substitutions: ({
      "code-url-handler": "visual-studio-code",
      "Code": "visual-studio-code",
      "gnome-tweaks": "org.gnome.tweaks",
      "pavucontrol-qt": "pavucontrol",
      "wps": "wps-office2019-kprometheus",
      "wpsoffice": "wps-office2019-kprometheus",
      "footclient": "foot"
    })

  readonly property var regexSubstitutions: [
    {
      "regex": /^steam_app_(\d+)$/,
      "replace": "steam_icon_$1"
    },
    {
      "regex": /Minecraft.*/,
      "replace": "minecraft"
    },
    {
      "regex": /.*polkit.*/,
      "replace": "system-lock-screen"
    },
    {
      "regex": /gcr.prompter/,
      "replace": "system-lock-screen"
    }
  ]

  // An icon's source if the theme has it, else the generic program icon's,
  // else "": an Image given a name the theme lacks logs `Could not load icon`
  function appIcon(name) {
    return (name ? Quickshell.iconPath(name, true) : "") || Quickshell.iconPath("application-x-executable", true);
  }

  function resolveWindowIcon(windowClass, windowTitle) {
    const baseIcon = appIcon(guessIcon(windowClass));
    // Special case for kitty running nvim
    if (baseIcon.includes("kitty") && windowTitle?.toLowerCase().includes("nvim"))
      return appIcon("nvim");
    return baseIcon;
  }

  function iconExists(iconName) {
    if (!iconName || iconName.length === 0 || iconName.includes("image-missing"))
      return false;
    return Quickshell.iconPath(iconName, true).length > 0;
  }

  // Best-effort icon name for a window class; returns the class itself when
  // nothing better is found
  function guessIcon(windowClass) {
    if (!windowClass || windowClass.length === 0)
      return "image-missing";

    const entry = DesktopEntries.heuristicLookup(windowClass);
    if (entry)
      return entry.icon;

    const lowercased = windowClass.toLowerCase();
    if (substitutions[windowClass])
      return substitutions[windowClass];
    if (substitutions[lowercased])
      return substitutions[lowercased];

    for (const sub of regexSubstitutions) {
      const replaced = windowClass.replace(sub.regex, sub.replace);
      if (replaced !== windowClass)
        return replaced;
    }

    // org.foo.AppName -> AppName, "App Name" -> app-name
    const reverseDomain = windowClass.split(".").slice(-1)[0];
    const candidates = [windowClass, lowercased, reverseDomain, reverseDomain.toLowerCase(), lowercased.replace(/\s+/g, "-")];
    for (const candidate of candidates) {
      if (iconExists(candidate))
        return candidate;
    }

    // Last resort: a desktop entry whose icon or name contains the class
    const apps = DesktopEntries.applications.values;
    const match = apps.find(a => a.icon?.toLowerCase().includes(lowercased)) ?? apps.find(a => a.name?.toLowerCase().includes(lowercased));
    if (match && iconExists(match.icon))
      return match.icon;

    return windowClass;
  }
}
