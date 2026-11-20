import QtQuick
import QtTest
import qs.config
import qs.components.content.Calendar
import qs.components.content.parts.calendar

// CalendarCard: a Calendar card without events (`showEvents: false`) is the
// plain month filling the card, never side by side or stacked and with no
// day pane built; with events it keeps both layouts.
TestCase {
  id: root

  name: "CalendarCard"
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

      Calendar {
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

  function card(emW, emH, showEvents) {
    const host = createTemporaryObject(hostComp, root, {
      "width": Appearance.fontSize * emW,
      "height": Appearance.fontSize * emH,
      "props": {
        "showEvents": showEvents,
        "calendars": [],
        "showWeekNumbers": false
      }
    });
    wait(50);
    return host.card;
  }

  function find(item, has) {
    if (item[has] !== undefined)
      return item;
    for (const child of item.children) {
      const hit = root.find(child, has);
      if (hit)
        return hit;
    }
    return null;
  }

  function test_without_events_the_month_alone_fills_the_card() {
    for (const size of [[40, 20], [20, 30]]) {
      const c = root.card(size[0], size[1], false);
      const grid = root.find(c, "cellHeight");
      verify(!c.sideBySide, size + " sideBySide");
      verify(!c.stacked, size + " stacked");
      verify(c.showGrid, size + " showGrid");
      verify(!c.showDay, size + " showDay");
      compare(root.find(c, "sourceComponent").item, null);
      verify(c.innerWidth > 0);
      compare(grid.width, c.innerWidth);
      compare(grid.height, c.innerHeight);
    }
  }

  function test_with_events_the_card_keeps_its_layouts() {
    verify(root.card(40, 20, true).sideBySide);
    verify(root.card(20, 30, true).stacked);
  }
}
