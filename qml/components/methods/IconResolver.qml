pragma Singleton
import QtQuick

/**
 * Guesses icon names for window classes: desktop entries first, then known
 * substitutions, then name variants that exist in the icon theme. Pure: the
 * caller (AppIconManager) hands it the theme and the desktop entries.
 * Substitution tables adapted from end-4's dots-hyprland.
 */
QtObject {
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

  // Best-effort icon name for a window class; returns the class itself when
  // nothing better is found. `lookup` holds `entry(cls)` (the desktop entry
  // for a class, or null), `exists(name)` (the icon theme has it) and
  // `apps()` (every desktop entry)
  function guessIcon(windowClass, lookup) {
    if (!windowClass || windowClass.length === 0)
      return "image-missing";

    const entry = lookup.entry(windowClass);
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
    const exists = name => !!name && !name.includes("image-missing") && lookup.exists(name);
    const candidates = [windowClass, lowercased, reverseDomain, reverseDomain.toLowerCase(), lowercased.replace(/\s+/g, "-")];
    for (const candidate of candidates) {
      if (exists(candidate))
        return candidate;
    }

    // Last resort: a desktop entry whose icon or name contains the class
    const apps = lookup.apps();
    const match = apps.find(a => a.icon?.toLowerCase().includes(lowercased)) ?? apps.find(a => a.name?.toLowerCase().includes(lowercased));
    if (match && exists(match.icon))
      return match.icon;

    return windowClass;
  }
}
