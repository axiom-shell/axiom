pragma Singleton
import QtQuick

/**
 * Dev mode's labels: a checkout as `branch@sha`, and the rows of
 * dev.config.diff (`{ path, side, dev?, live?, devOnly }`, a path of keys
 * and `{ id }` list items) as the Development settings show them: the
 * setting's titles from the schema, each side's value as short text, and
 * which side changed it.
 */
QtObject {
  id: root

  // Values longer than this are cut, with "…"
  readonly property int valueLength: 80

  // `branch@sha` (the commit's first 7), `*` after it with changes; the
  // commit alone without a branch, "" without a commit
  function checkout(branch, commit, dirty) {
    if (!commit)
      return "";
    const sha = String(commit).slice(0, 7) + (dirty ? "*" : "");
    return branch ? branch + "@" + sha : sha;
  }

  // The schema node at `node`, its `$ref` replaced by the definition
  function _resolved(node, schema) {
    if (!node?.$ref)
      return node;
    return schema?.definitions?.[node.$ref.replace("#/definitions/", "")] ?? null;
  }

  // A row's path as titled parts, [{ text, schema }]: a key's schema
  // title (`schema` true: a schema string to translate), else the key
  // itself; a list item's id (`{ id }`). A path has no item's type, so
  // under a `oneOf` (a bar widget, a module) every option is followed:
  // a key is titled when the options that have it agree on its title
  function titleParts(schema, path) {
    const parts = [];
    let nodes = [schema];
    for (const segment of path ?? []) {
      nodes = [].concat(...nodes.map(node => node?.oneOf ? node.oneOf.map(option => root._resolved(option, schema)) : [node]));
      if (segment !== null && typeof segment === "object") {
        nodes = nodes.map(node => root._resolved(node?.items, schema));
        parts.push({
          "text": String(segment.id),
          "schema": false
        });
        continue;
      }
      nodes = nodes.map(node => root._resolved(node?.properties?.[segment], schema)).filter(node => node);
      const titles = new Set(nodes.map(node => node.title));
      const title = titles.size === 1 ? nodes[0].title : undefined;
      parts.push({
        "text": title ? title : String(segment),
        "schema": !!title
      });
    }
    return parts;
  }

  // Whether the row has a value on `side` ("dev" or "live"): a missing
  // key is left out of the row
  function has(row, side) {
    return row !== null && typeof row === "object" && side in row;
  }

  // The row's value on `side` as one line of text: a string as it is,
  // anything else as JSON, cut at `valueLength`; "" when it has none
  function valueText(row, side) {
    if (!root.has(row, side))
      return "";
    const value = row[side];
    const text = typeof value === "string" ? value : JSON.stringify(value);
    const line = String(text).replace(/\s+/g, " ");
    return line.length > root.valueLength ? line.slice(0, root.valueLength - 1) + "…" : line;
  }

  // Which side changed it since the base, as an English label to
  // translate
  function sideLabel(side) {
    return ({
        "dev": "Changed in dev",
        "live": "Changed in live",
        "both": "Changed in both"
      })[side] ?? "";
  }

  // Whether the row can be copied to live: a dev-only setting can't
  function toLive(row) {
    return row?.devOnly !== true;
  }
}
