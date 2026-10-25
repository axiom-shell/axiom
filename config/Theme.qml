pragma Singleton

import QtQuick

import qs.services.core

// The active theme's colors: base16 (base00-base0F) and semantic names,
// filled from theme-defaults.json; resolveColor(name) for names from config.
QtObject {
  id: root

  property var _themeData: ThemeManager.currentTheme

  // Defaults for what a theme leaves out (config/json/theme-defaults.json)
  readonly property var _defaultColors: ThemeManager.defaults.colors
  readonly property var _defaultSemantic: ThemeManager.defaults.semantic[_themeData.variant === "light" ? "light" : "dark"]

  // A semantic color: the base16 key (or color) the theme maps it to, else
  // the default mapping
  function _semantic(name) {
    const key = _themeData.semantic?.[name] ?? _defaultSemantic[name];
    return root[key] ?? key;
  }

  // --- Base16 colors ---
  readonly property color base00: _themeData.colors?.base00 ?? _defaultColors.base00
  readonly property color base01: _themeData.colors?.base01 ?? _defaultColors.base01
  readonly property color base02: _themeData.colors?.base02 ?? _defaultColors.base02
  readonly property color base03: _themeData.colors?.base03 ?? _defaultColors.base03
  readonly property color base04: _themeData.colors?.base04 ?? _defaultColors.base04
  readonly property color base05: _themeData.colors?.base05 ?? _defaultColors.base05
  readonly property color base06: _themeData.colors?.base06 ?? _defaultColors.base06
  readonly property color base07: _themeData.colors?.base07 ?? _defaultColors.base07
  readonly property color base08: _themeData.colors?.base08 ?? _defaultColors.base08
  readonly property color base09: _themeData.colors?.base09 ?? _defaultColors.base09
  readonly property color base0A: _themeData.colors?.base0A ?? _defaultColors.base0A
  readonly property color base0B: _themeData.colors?.base0B ?? _defaultColors.base0B
  readonly property color base0C: _themeData.colors?.base0C ?? _defaultColors.base0C
  readonly property color base0D: _themeData.colors?.base0D ?? _defaultColors.base0D
  readonly property color base0E: _themeData.colors?.base0E ?? _defaultColors.base0E
  readonly property color base0F: _themeData.colors?.base0F ?? _defaultColors.base0F

  // --- Semantic colors ---
  readonly property color background: _semantic("background")
  readonly property color backgroundAlt: _semantic("backgroundAlt")
  readonly property color backgroundHighlight: _semantic("backgroundHighlight")
  readonly property color foreground: _semantic("foreground")
  readonly property color foregroundAlt: _semantic("foregroundAlt")
  readonly property color foregroundHighlight: _semantic("foregroundHighlight")
  readonly property color foregroundInactive: _semantic("foregroundInactive")
  readonly property color border: _semantic("border")
  readonly property color borderFocus: _semantic("borderFocus")
  readonly property color accent: _semantic("accent")
  readonly property color accentAlt: _semantic("accentAlt")
  readonly property color success: _semantic("success")
  readonly property color warning: _semantic("warning")
  readonly property color error: _semantic("error")
  readonly property color info: _semantic("info")
  readonly property color red: _semantic("red")
  readonly property color green: _semantic("green")
  readonly property color yellow: _semantic("yellow")
  readonly property color blue: _semantic("blue")
  readonly property color magenta: _semantic("magenta")
  readonly property color cyan: _semantic("cyan")
  readonly property color orange: _semantic("orange")
  readonly property color grey: _semantic("grey")
  readonly property color bg0: _semantic("bg0")
  readonly property color bg1: _semantic("bg1")
  readonly property color bg2: _semantic("bg2")
  readonly property color fg3: _semantic("fg3")
  readonly property color fg2: _semantic("fg2")
  readonly property color fg1: _semantic("fg1")

  readonly property var stringToColorMap: ({
      "base00": base00,
      "base01": base01,
      "base02": base02,
      "base03": base03,
      "base04": base04,
      "base05": base05,
      "base06": base06,
      "base07": base07,
      "base08": base08,
      "base09": base09,
      "base0A": base0A,
      "base0B": base0B,
      "base0C": base0C,
      "base0D": base0D,
      "base0E": base0E,
      "base0F": base0F,
      "background": background,
      "backgroundAlt": backgroundAlt,
      "backgroundHighlight": backgroundHighlight,
      "foreground": foreground,
      "foregroundAlt": foregroundAlt,
      "foregroundHighlight": foregroundHighlight,
      "foregroundInactive": foregroundInactive,
      "border": border,
      "borderFocus": borderFocus,
      "accent": accent,
      "accentAlt": accentAlt,
      "success": success,
      "warning": warning,
      "error": error,
      "info": info,
      "red": red,
      "green": green,
      "yellow": yellow,
      "blue": blue,
      "magenta": magenta,
      "cyan": cyan,
      "orange": orange,
      "grey": grey,
      "bg0": bg0,
      "bg1": bg1,
      "bg2": bg2,
      "fg3": fg3,
      "fg2": fg2,
      "fg1": fg1
    })

  // --- Metadata ---
  readonly property string name: _themeData.name ?? "Unknown"
  readonly property string variant: _themeData.variant ?? "dark"
  readonly property string paired: _themeData.paired ?? ""
  property bool isGenerated: false

  // The 16 base colors offered by color pickers (`x-options: "colors"`)
  readonly property var baseColorNames: ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07", "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"]

  // Every semantic name (theme-defaults' order, then any the theme adds)
  // by the base color it maps to in this theme: { base0D: ["accentAlt",
  // "blue"], … }. Names mapped to a hex rather than a base are left out.
  readonly property var roles: {
    const own = root._themeData.semantic ?? {};
    const names = Object.keys(root._defaultSemantic).concat(Object.keys(own).filter(name => !(name in root._defaultSemantic)));
    return names.reduce((result, name) => {
      const key = own[name] ?? root._defaultSemantic[name];
      if (root.baseColorNames.includes(key))
        result[key] = (result[key] ?? []).concat(name);
      return result;
    }, {});
  }

  // Color from a config string: a base key ("base0C"), a semantic name
  // ("info") or anything Qt parses as a color ("#ff5733"). Reading
  // stringToColorMap here makes callers' bindings re-evaluate when the
  // theme changes.
  function resolveColor(name) {
    const map = root.stringToColorMap;
    if (!name)
      return "transparent";
    return map[name] ?? name;
  }

  Component.onCompleted: {
    console.log("------------------ " + "Initialized : " + Appearance.theme + " ------------------");
  }
}
