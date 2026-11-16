import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.views.BarEditor

// LayoutOverrideField: the schema's automatic-number shape: a switch for
// setting the override by hand, the stepper only while it is set; a null value
// reads as unset, and turning it off says undefined.
TestCase {
  id: root

  name: "LayoutOverrideField"
  when: windowShown
  visible: true
  width: 500
  height: 400

  Harness {
    id: harness
  }

  Component {
    id: hostComp

    ColumnLayout {
      property alias field: inner
      property var emitted: []

      width: 420

      LayoutOverrideField {
        id: inner

        Layout.fillWidth: true
        key: "maxSize"
        fieldSchema: ({
            "title": "Maximum length",
            "minimum": 0,
            "maximum": 500
          })
        initial: 40
        onEdited: value => parent.emitted = parent.emitted.concat([value === undefined ? "unset" : value])
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function find(item, test, out) {
    if (test(item))
      out.push(item);
    for (const child of item.children)
      root.find(child, test, out);
    return out;
  }

  function stepper(host) {
    return root.find(host, item => item.currentConfigValue !== undefined && item.mode !== undefined, [])[0];
  }

  function test_unset_shows_only_the_switch() {
    const host = createTemporaryObject(hostComp, root);
    waitForRendering(host);
    verify(!host.field.isSet);
    verify(!root.stepper(host).visible, "no number while unset");
    host.field.value = null;
    verify(!host.field.isSet, "null reads as unset");
  }

  function test_switch_sets_and_unsets() {
    const host = createTemporaryObject(hostComp, root);
    waitForRendering(host);
    host.field.activates.activate();
    compare(host.emitted, [40], "turning it on starts at `initial`");
    host.field.value = 40;
    waitForRendering(host);
    verify(root.stepper(host).visible, "the stepper shows while set");
    host.field.activates.activate();
    compare(host.emitted, [40, "unset"], "turning it off removes the override");
  }
}
