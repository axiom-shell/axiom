import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.forms
import qs.components.reusable
import qs.components.views.Settings

// One schema field as a row on every host (SchemaFormRow): a form given
// `changedAt` (SchemaPropertiesForm), the onboarder's SettingRows and the
// settings page's SettingsField each draw the field's reset button and its
// `x-link`s from the one piece, and a form with no marks hook draws none.
TestCase {
  id: root

  name: "SchemaFormRow"
  when: windowShown
  visible: true
  width: 600
  height: 600

  Harness {
    id: harness
  }

  // A boolean at false whose default is true: off its default
  readonly property var flag: ({
      "type": "boolean",
      "title": "Flag",
      "default": true,
      "x-link": {
        "setting": "Other.thing"
      }
    })

  function findAll(item, test) {
    const out = [];
    const walk = it => {
      if (test(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  function marks(item) {
    return root.findAll(item, it => it.atDefault !== undefined && it.defaultText !== undefined);
  }

  function links(item) {
    return root.findAll(item, it => it.follow !== undefined && it.setting !== undefined);
  }

  function init() {
    harness.configure({});
    SettingsManager.schemas = {
      "Test.flag": root.flag
    };
    SettingsManager.values = {
      "Test.flag": false
    };
    SettingsManager.located = {
      "Other.thing": {
        "title": "Thing",
        "category": "Other"
      }
    };
    SettingsManager.discarded = [];
  }

  Component {
    id: formComp

    SchemaPropertiesForm {
      id: form
      property var edits: []
      property var discards: []
      property bool marked: true
      property bool withAction: false
      width: 500
      propertiesSchema: ({
          "flag": root.flag
        })
      values: ({
          "flag": false
        })
      changedAt: form.marked ? path => true : null
      fieldAction: form.withAction ? (path, schema) => ({
            "text": "Do it",
            "icon": "add",
            "run": () => form.edits.push("ran")
          }) : null
      onEdited: (path, value) => form.edits.push([path, value])
      onDiscardAt: path => form.discards.push(path)
    }
  }

  function test_form_marks_and_links() {
    const form = createTemporaryObject(formComp, root);
    verify(form);
    tryVerify(() => root.marks(form).length === 1);
    const mark = root.marks(form)[0];
    compare(mark.atDefault, false, "the reset button shows off the default");
    compare(mark.changed, true);
    tryVerify(() => root.links(form).length === 1 && root.links(form)[0].visible, 1000, "the x-link under the field");
    mark.reset(true);
    compare(form.edits[0][0], ["flag"]);
    compare(form.edits[0][1], true);
    mark.discard();
    compare(form.discards, [["flag"]]);
  }

  function test_form_without_changed_at_has_no_marks() {
    const form = createTemporaryObject(formComp, root, {
      "marked": false
    });
    verify(form);
    tryVerify(() => root.links(form).length === 1, 1000);
    compare(root.marks(form).length, 0);
  }

  function test_form_action_is_a_link() {
    const form = createTemporaryObject(formComp, root, {
      "withAction": true
    });
    verify(form);
    tryVerify(() => root.links(form).filter(l => l.text === "Do it").length === 1, 1000);
    const link = root.links(form).filter(l => l.text === "Do it")[0];
    compare(link.icon, "add");
    link.follow();
    compare(form.edits, ["ran"]);
  }

  Component {
    id: rowsComp

    SettingRows {
      id: rows
      property var edits: []
      width: 500
      paths: ["Test.flag"]
      onEdited: (path, value) => rows.edits.push([path, value])
    }
  }

  // The onboarder's rows get the reset button and the links too
  function test_setting_rows_marks_and_links() {
    const rows = createTemporaryObject(rowsComp, root);
    verify(rows);
    tryVerify(() => root.marks(rows).length === 1);
    const mark = root.marks(rows)[0];
    compare(mark.atDefault, false);
    compare(mark.changed, false, "its edits save at once: no unsaved dot");
    tryVerify(() => root.links(rows).length === 1 && root.links(rows)[0].visible, 1000);
    mark.reset(true);
    compare(rows.edits[0][0], ["Test", "flag"]);
    compare(rows.edits[0][1], true);
  }

  Component {
    id: fieldComp

    Item {
      id: host
      property alias field: field
      width: 500
      height: 200

      QtObject {
        id: form
        signal edited(var path, var value)
        property bool listing: false
        function valueAt(path) {
          return false;
        }
        function edit(path, value) {
          form.edited(path, value);
        }
        function rowShown(row) {
          return true;
        }
      }

      SettingsField {
        id: field
        width: parent.width
        form: form
        row: ({
            "kind": "field",
            "title": "Flag",
            "path": ["Test", "flag"],
            "schema": root.flag
          })
      }
    }
  }

  function test_settings_field_marks_and_links() {
    const host = createTemporaryObject(fieldComp, root);
    verify(host);
    tryVerify(() => root.marks(host).length === 1);
    const mark = root.marks(host)[0];
    compare(mark.atDefault, false);
    tryVerify(() => root.links(host).length === 1 && root.links(host)[0].visible, 1000);
    mark.discard();
    compare(SettingsManager.discarded, [["Test", "flag"]]);
    verify(host.field.height > 0);
    verify(host.field.fieldHeight > 0);
  }

  // Only SchemaPropertiesForm's cells stream; the other hosts build the
  // field with the row, so `fieldShown` is known at once
  function test_only_the_form_streams() {
    BuildQueueManager.labels = [];
    const rows = createTemporaryObject(rowsComp, root);
    verify(rows);
    const host = createTemporaryObject(fieldComp, root);
    verify(host);
    compare(BuildQueueManager.labels.filter(l => l === "form field"), [], "no request");
    const cells = root.findAll(rows, it => it.fieldShown !== undefined);
    verify(cells.length > 0);
    for (const cell of cells)
      compare(typeof cell.fieldShown, "boolean");
    compare(typeof host.field.fieldShown, "boolean");
    BuildQueueManager.labels = [];
    const form = createTemporaryObject(twoFormComp, root);
    verify(form);
    compare(BuildQueueManager.labels.filter(l => l === "form field").length, 2);
  }

  Component {
    id: twoFormComp

    SchemaPropertiesForm {
      width: 500
      propertiesSchema: ({
          "a": root.flag,
          "b": root.flag
        })
      values: ({
          "a": false,
          "b": false
        })
    }
  }
}
