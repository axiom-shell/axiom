pragma Singleton
import QtQuick

// Groups themes into the families the theme list shows (a dark/light pair
// is one theme) and finds the family a theme name belongs to, for
// ThemeManager. No file access, processes or services.
QtObject {
  id: root

  // `themes`: [{ name, label, variant, paired, preview }]. Returns one family
  // { label, dark, light, darkPreview, lightPreview, shared, generated,
  // community } per dark theme and per light theme no dark joins, sorted by
  // label. A light names one dark back: that pair is the family's main one,
  // labelled by the words their names share ("Tokyo Night" + "Tokyo Day" =
  // "Tokyo"); every other dark naming it shares it (`shared`) and keeps its
  // own label ("Tokyo Storm"). A dark naming a light that names no dark
  // back as its pair stays a theme on its own, as does that light.
  function build(themes, generated, community = false) {
    const byName = themes.reduce((map, theme) => {
      map[theme.name] = theme;
      return map;
    }, {});
    const named = (theme, variant) => {
      const pair = byName[theme.paired];
      return pair && pair.variant === variant ? pair : null;
    };
    // The light a dark joins: the one it names, while that light's own
    // dark names it back
    const lightOf = theme => {
      const light = theme.variant === "dark" ? named(theme, "light") : null;
      const main = light ? named(light, "dark") : null;
      return main && main.paired === light.name ? light : null;
    };
    const claimed = {};
    const families = [];
    const add = (dark, light, label, shared) => families.push({
        "label": label,
        "dark": dark?.name ?? "",
        "light": light?.name ?? "",
        "darkPreview": dark?.preview ?? null,
        "lightPreview": light?.preview ?? null,
        "shared": shared,
        "generated": generated,
        "community": community
      });
    for (const theme of themes) {
      const light = lightOf(theme);
      if (!light)
        continue;
      claimed[light.name] = true;
      const main = light.paired === theme.name;
      add(theme, light, main ? root.commonLabel(theme.label, light.label) : theme.label, !main);
    }
    for (const theme of themes) {
      if (theme.variant === "dark" ? !lightOf(theme) : !claimed[theme.name])
        add(theme.variant === "dark" ? theme : null, theme.variant === "light" ? theme : null, theme.label, false);
    }
    return families.sort((a, b) => a.label.localeCompare(b.label));
  }

  // The leading words `a` and `b` share, or `a` when they share none
  function commonLabel(a, b) {
    const wordsA = a.split(" ");
    const wordsB = b.split(" ");
    let n = 0;
    while (n < wordsA.length && n < wordsB.length && wordsA[n] === wordsB[n])
      n++;
    return n > 0 ? wordsA.slice(0, n).join(" ") : a;
  }

  // The family `theme` belongs to, or null. A light several families share
  // belongs to the one whose dark is `lightFrom` (the dark it was switched
  // to light from), else to its main family.
  function current(families, theme, lightFrom) {
    const withLight = families.filter(family => family.light === theme);
    return families.find(family => family.dark === theme) ?? withLight.find(family => family.dark === lightFrom) ?? withLight.find(family => !family.shared) ?? withLight[0] ?? null;
  }

  // The preview ({ background, foreground, accent, colors }) of the theme
  // named `theme`, the variant it is, or null for one no family has
  function previewOf(families, theme) {
    for (const family of families) {
      if (family.dark === theme && family.darkPreview)
        return family.darkPreview;
      if (family.light === theme && family.lightPreview)
        return family.lightPreview;
    }
    return null;
  }
}
