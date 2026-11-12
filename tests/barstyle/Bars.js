// The bar fixture for the bar tests: an enriched bar (BarEnrich.enrich, the
// real path BarsConfig.enrichBarConfig takes) from the schema's defaults
// with `rawOver` on top. Not a pragma library: BarEnrich is the importing
// test's. QML_XHR_ALLOW_FILE_READ (scripts/run_tests.sh) lets it read the
// built schema, as RepoFiles does.
//
//   Bars.bar(rawOver, envOver)
//     rawOver  a bar entry's keys (thickness, location, surface, …); its
//              BarStyle keys (textScale, widgetStyle, …, shadow as
//              { enabled, color, size }) are the Bars section's style, the
//              bar's own `style` left to inherit it
//     envOver  keys of BarEnrich's env to replace
//   Bars.env(over)   that env: Theme and Appearance stand-ins
//   Bars.defaults(name)   a schema definition's defaults

var _schema = null;

function schema() {
  if (_schema === null) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", Qt.resolvedUrl("../../qml/config/json/config.schema.json"), false);
    xhr.send();
    _schema = JSON.parse(xhr.responseText);
  }
  return _schema;
}

// The defaults of a definition's properties (an object property's, nested)
function defaults(name) {
  const walk = def => Object.keys(def.properties).reduce((out, key) => {
    const property = def.properties[key];
    if (property.type === "object" && property.properties)
      out[key] = walk(property);
    else if ("default" in property)
      out[key] = property.default;
    return out;
  }, {});
  return walk(schema().definitions[name]);
}

// Theme stand-ins: what Theme.resolveColor gives for a name
var theme = {
  "foreground": "#ebdbb2",
  "background": "#282828",
  "backgroundAlt": "#3c3836",
  "backgroundHighlight": "#504945",
  "accent": "#83a598",
  "accentAlt": "#d3869b",
  "base00": "#282828",
  "base01": "#3c3836",
  "base02": "#504945",
  "base03": "#665c54",
  "base04": "#bdae93",
  "base05": "#d5c4a1",
  "base06": "#ebdbb2",
  "base07": "#fbf1c7",
  "base08": "#fb4934",
  "base09": "#fe8019",
  "base0A": "#fabd2f",
  "base0B": "#b8bb26",
  "base0C": "#8ec07c",
  "base0D": "#458588",
  "base0E": "#d3869b",
  "base0F": "#d65d0e",
  "warning": "#fabd2f",
  "error": "#fb4934",
  "success": "#98971a",
  "border": "#665c54"
};

// The same names in a light theme (a base16 light scheme)
var lightTheme = {
  "foreground": "#3c3836",
  "background": "#fbf1c7",
  "backgroundAlt": "#ebdbb2",
  "backgroundHighlight": "#d5c4a1",
  "accent": "#076678",
  "accentAlt": "#8f3f71",
  "base00": "#fbf1c7",
  "base01": "#ebdbb2",
  "base02": "#d5c4a1",
  "base03": "#bdae93",
  "base04": "#665c54",
  "base05": "#504945",
  "base06": "#3c3836",
  "base07": "#282828",
  "base08": "#9d0006",
  "base09": "#af3a03",
  "base0A": "#b57614",
  "base0B": "#79740e",
  "base0C": "#427b58",
  "base0D": "#076678",
  "base0E": "#8f3f71",
  "base0F": "#d65d0e",
  "warning": "#b57614",
  "error": "#9d0006",
  "success": "#79740e",
  "border": "#bdae93"
};

function resolverOf(colors) {
  return name => Qt.color(colors[name] ?? name);
}

function resolve(name) {
  return Qt.color(theme[name] ?? name);
}

// The env keys that make a theme: its resolver, foreground and background
function themeEnv(colors) {
  return {
    "resolve": resolverOf(colors),
    "foreground": Qt.color(colors.foreground),
    "background": Qt.color(colors.background)
  };
}

// The Auto color fields of the schema's widget types (BarEnrich's)
function autoColorFields() {
  return BarEnrich.autoColorFields(schema());
}

function env(over) {
  return Object.assign({
    "barStyle": defaults("BarStyle"),
    "radius": 12,
    "widgetRadius": 8,
    "baseFontSize": 14,
    "borderWidth": 1,
    "screenBorder": false,
    "screenMargin": 8,
    "resolve": resolve,
    "foreground": resolve("foreground"),
    "background": resolve("background"),
    "outputs": [],
    "redForGains": false,
    "autoColorFields": autoColorFields(),
    "baseColorNames": ["base00", "base01", "base02", "base03", "base04", "base05", "base06", "base07", "base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"]
  }, over);
}

function bar(rawOver, envOver) {
  const styleKeys = Object.keys(schema().definitions.BarStyle.properties);
  const section = {};
  const own = {};
  Object.keys(rawOver ?? {}).forEach(key => (styleKeys.includes(key) ? section : own)[key] = rawOver[key]);
  const base = env();
  const config = Object.assign(defaults("Bar"), {
    "id": "test",
    "monitor": "",
    "style": {},
    "widgets": {
      "left": [],
      "center": [],
      "right": []
    }
  }, own);
  return BarEnrich.enrich(config, {}, {}, env(Object.assign({
    "barStyle": Object.assign({}, base.barStyle, section)
  }, envOver)));
}
