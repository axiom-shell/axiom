import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.content.Battery

// BatteryModule: with showPowerProfile off the profile row takes no height and
// no gap (its top margin follows the row, not just the battery); on, it
// takes both.
TestCase {
  id: root

  name: "BatteryModule"
  when: windowShown
  visible: true
  width: 900
  height: 700

  Harness {
    id: harness
  }

  Component {
    id: hostComp

    Item {
      property alias card: inner
      property var props: ({})

      Battery {
        id: inner

        embedded: true
        properties: parent.props
        anchors.fill: parent
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function card(showPowerProfile) {
    const host = createTemporaryObject(hostComp, root, {
      "width": Appearance.fontSize * 20,
      "height": Appearance.fontSize * 30,
      "props": {
        "showPowerProfile": showPowerProfile,
        "showPeripherals": false,
        "showTime": true
      }
    });
    wait(50);
    return host.card;
  }

  // The profile row: the card's only SegmentRow
  function profileRow(item) {
    if (item._pickable !== undefined)
      return item;
    for (const child of item.children) {
      const hit = root.profileRow(child);
      if (hit)
        return hit;
    }
    return null;
  }

  function test_profile_row_off_takes_no_gap() {
    const row = root.profileRow(root.card(false));
    verify(row !== null, "profile row found");
    compare(row.Layout.topMargin, 0);
    compare(row.Layout.maximumHeight, 0);
  }

  function test_profile_row_on_takes_its_gap() {
    const row = root.profileRow(root.card(true));
    verify(row !== null, "profile row found");
    compare(row.Layout.topMargin, Widget.spacing);
    verify(row.height > 0);
  }
}
