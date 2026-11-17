import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms

// SettingsLink: in less room than its label needs, the label elides.
TestCase {
  id: root

  name: "SettingsLink"
  when: windowShown
  visible: true
  width: 500
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: linkComp

    SettingsLink {
      width: 60
      text: "A very long link label that cannot fit"
      run: () => {}
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function labelOf(item) {
    if (item.paintedWidth !== undefined && item.text === "A very long link label that cannot fit")
      return item;
    for (const child of item.children) {
      const found = labelOf(child);
      if (found)
        return found;
    }
    return null;
  }

  function test_long_label_elides() {
    const link = createTemporaryObject(linkComp, root);
    verify(link);
    waitForRendering(link);
    const label = root.labelOf(link);
    verify(label);
    verify(label.truncated, "elided in 60 px: label " + label.width);
    verify(label.width < 60, "within the link's width");
  }
}
