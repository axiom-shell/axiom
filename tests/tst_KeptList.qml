import QtQuick
import QtTest

// KeptList (services/core, loaded from its file as tst_EditHistory loads
// EditHistory): a rebuilt list with equal content is the same array and
// objects and notifies nothing; oncePerTurn keeps once per event turn
TestCase {
  id: root

  name: "KeptList"

  property int notified: 0

  function make(props) {
    const component = Qt.createComponent(Qt.resolvedUrl("../qml/services/core/KeptList.qml"));
    compare(component.status, Component.Ready, component.errorString());
    const list = createTemporaryObject(component, root, props);
    verify(list);
    return list;
  }

  function test_unchanged_list_doesnt_notify() {
    const list = make({
      "fresh": [
        {
          "id": "a",
          "v": 1
        },
        {
          "id": "b",
          "v": 2
        }
      ]
    });
    const before = list.items;
    root.notified = 0;
    list.itemsChanged.connect(() => root.notified++);
    list.fresh = [
      {
        "id": "a",
        "v": 1
      },
      {
        "id": "b",
        "v": 2
      }
    ];
    verify(list.items === before, "the same array");
    compare(root.notified, 0, "no notify");
  }

  function test_changed_entry() {
    const list = make({
      "fresh": [
        {
          "id": "a",
          "v": 1
        },
        {
          "id": "b",
          "v": 2
        }
      ]
    });
    const before = list.items;
    root.notified = 0;
    list.itemsChanged.connect(() => root.notified++);
    list.fresh = [
      {
        "id": "a",
        "v": 1
      },
      {
        "id": "b",
        "v": 3
      }
    ];
    verify(list.items !== before);
    verify(list.items[0] === before[0], "the equal entry is kept");
    verify(list.items[1] !== before[1], "the changed entry is new");
    compare(list.items[1].v, 3);
    compare(root.notified, 1);
  }

  function test_id_of_is_used() {
    const list = make({
      "fresh": [
        {
          "name": "a"
        },
        {
          "name": "b"
        }
      ],
      "idOf": e => e.name
    });
    const before = list.items;
    list.fresh = [
      {
        "name": "b"
      },
      {
        "name": "a"
      }
    ];
    verify(list.items[0] === before[1]);
    verify(list.items[1] === before[0]);
  }

  function test_once_per_turn() {
    const list = make({
      "oncePerTurn": true
    });
    root.notified = 0;
    list.itemsChanged.connect(() => root.notified++);
    list.fresh = [
      {
        "id": "a"
      }
    ];
    list.fresh = [
      {
        "id": "a"
      },
      {
        "id": "b"
      }
    ];
    list.fresh = [
      {
        "id": "c"
      }
    ];
    compare(list.items.length, 0, "not kept synchronously");
    wait(0);
    compare(list.items.length, 1);
    compare(list.items[0].id, "c");
    compare(root.notified, 1);
  }

  function test_two_parts_once_per_turn() {
    const one = make({
      "oncePerTurn": true
    });
    const two = make({
      "oncePerTurn": true
    });
    one.fresh = [
      {
        "id": "a"
      }
    ];
    two.fresh = [
      {
        "id": "b"
      }
    ];
    wait(0);
    compare(one.items[0].id, "a");
    compare(two.items[0].id, "b");
  }

  function test_not_once_per_turn_is_synchronous() {
    const list = make({});
    list.fresh = [
      {
        "id": "a"
      }
    ];
    compare(list.items.length, 1);
  }

  function test_completion_keeps_fresh() {
    const list = make({
      "fresh": [
        {
          "id": "a"
        },
        {
          "id": "b"
        }
      ]
    });
    compare(list.items.length, 2);
  }
}
