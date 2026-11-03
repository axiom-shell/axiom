pragma Singleton
import QtQuick

// The settings page's search: what each card and row can be found by,
// lowercased once (`index`), and the cards matching a query or the
// changed set (`filter`), so typing only runs `includes` on strings. No
// file access, processes or services.
QtObject {
  id: root

  // `groups`: SchemaLayout.categoryGroups() entries (hand-built cards
  // left out by the caller). `tr`: text -> its translation. Returns
  // [{ group, hay, rows: [{ row, hay }] }]: a card's hay its title and
  // section, a row's its title, description and key, each in English and
  // translated (a nested object's row has none: it's never a match itself)
  function index(groups, tr) {
    const hay = texts => texts.filter(text => !!text).map(text => text === tr(text) ? text : text + "\n" + tr(text)).join("\n").toLowerCase();
    return groups.map(group => ({
          "group": group,
          "hay": hay([group.title, group.section]),
          "rows": group.rows.map(row => ({
                "row": row,
                "hay": row.kind === "group" ? "" : hay([row.title, row.schema?.description]) + "\n" + row.path[row.path.length - 1].toLowerCase()
              }))
        }));
  }

  // The cards of `entries` (an `index`) with only their rows matching
  // `query` (lowercase; "" matches all), and with `changedOnly` only
  // settings in `changedSet` (dotted path -> true). A card whose title or
  // section matches keeps every row. Cards left empty are dropped
  function filter(entries, query, changedSet, changedOnly) {
    const result = [];
    for (const entry of entries) {
      const titleMatches = query === "" || entry.hay.includes(query);
      const rows = entry.rows.filter(item => (titleMatches || item.hay.includes(query)) && (!changedOnly || (item.row.kind !== "group" && changedSet[item.row.path.join(".")] === true))).map(item => item.row);
      if (rows.length > 0)
        result.push(Object.assign({}, entry.group, {
          "rows": rows
        }));
    }
    return result;
  }
}
