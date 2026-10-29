import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SettingsSearch"

  function row(path, title, description) {
    return {
      "kind": "value",
      "path": path,
      "title": title,
      "schema": {
        "description": description
      }
    };
  }

  readonly property var groups: [
    {
      "key": "Clock",
      "title": "Clock",
      "section": "Time",
      "rows": [row(["Clock", "format"], "Format", "How the time reads"), row(["Clock", "seconds"], "Seconds", "")]
    },
    {
      "key": "Bar",
      "title": "Bar",
      "section": "Bar",
      "rows": [
        {
          "kind": "group",
          "path": ["Bar", "shape"],
          "title": "Shape"
        },
        row(["Bar", "height"], "Height", "In pixels")]
    }
  ]

  function tr(text) {
    return text === "Height" ? "Höhe" : text;
  }

  function keys(groups) {
    return groups.map(group => group.key + ":" + group.rows.map(row => row.path.join(".")).join(","));
  }

  function test_title_keeps_every_row() {
    const index = SettingsSearch.index(groups, tr);
    compare(keys(SettingsSearch.filter(index, "time", {}, false)), ["Clock:Clock.format,Clock.seconds"], "the section matches");
  }

  function test_row_matches() {
    const index = SettingsSearch.index(groups, tr);
    compare(keys(SettingsSearch.filter(index, "reads", {}, false)), ["Clock:Clock.format"], "by description");
    compare(keys(SettingsSearch.filter(index, "höhe", {}, false)), ["Bar:Bar.height"], "by translation");
    compare(keys(SettingsSearch.filter(index, "seconds", {}, false)), ["Clock:Clock.seconds"], "by title or key");
    compare(keys(SettingsSearch.filter(index, "shape", {}, false)), [], "a nested object's row never matches itself");
  }

  function test_changed() {
    const index = SettingsSearch.index(groups, tr);
    const changed = {
      "Clock.seconds": true,
      "Bar.height": true
    };
    compare(keys(SettingsSearch.filter(index, "", changed, true)), ["Clock:Clock.seconds", "Bar:Bar.height"]);
    compare(keys(SettingsSearch.filter(index, "pixels", changed, true)), ["Bar:Bar.height"], "a query narrows the changed set");
  }

  function test_empty() {
    const index = SettingsSearch.index(groups, tr);
    compare(SettingsSearch.filter(index, "zzz", {}, false), []);
    compare(SettingsSearch.filter(SettingsSearch.index([], tr), "a", {}, false), []);
  }

  function test_keeps_group_fields() {
    const found = SettingsSearch.filter(SettingsSearch.index(groups, tr), "format", {}, false);
    compare(found[0].title, "Clock");
    compare(groups[0].rows.length, 2, "the input isn't changed");
  }
}
