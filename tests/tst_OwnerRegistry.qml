import QtQuick
import QtTest

// OwnerRegistry (services/core, loaded from its file as tst_KeptList loads
// KeptList): one entry per owner in the order owners first set; an equal
// value, a QObject value compared by identity, and dropping an unknown owner
// notify nothing
TestCase {
  id: root

  name: "OwnerRegistry"

  property int notified: 0

  readonly property var ownerA: ({
      "name": "a"
    })
  readonly property var ownerB: ({
      "name": "b"
    })
  readonly property var ownerC: ({
      "name": "c"
    })

  Component {
    id: itemComponent

    Item {}
  }

  // `steps`: [verb, owner, value?]; `owners`: the owner names in order
  // after them; `values`: what they hold; `notifies`: entries changes
  function test_steps_data() {
    return [
      {
        "tag": "SVC-01",
        "steps": [["set", "a",
            {
              x: 1
            }
          ]],
        "owners": ["a"],
        "values": [
          {
            x: 1
          }
        ],
        "notifies": 1
      },
      {
        "tag": "SVC-02",
        "steps": [["set", "a",
            {
              x: 1,
              y: 2
            }
          ], ["set", "a",
            {
              y: 2,
              x: 1
            }
          ]],
        "owners": ["a"],
        "values": [
          {
            x: 1,
            y: 2
          }
        ],
        "notifies": 1
      },
      {
        "tag": "SVC-03",
        "steps": [["set", "a", 1], ["set", "b", 1], ["set", "a", 2]],
        "owners": ["a", "b"],
        "values": [2, 1],
        "notifies": 3
      },
      {
        "tag": "SVC-04",
        "steps": [["set", "a", 1], ["drop", "c"]],
        "owners": ["a"],
        "values": [1],
        "notifies": 1
      },
      {
        "tag": "SVC-05",
        "steps": [["set", "a", 1], ["drop", "a"]],
        "owners": [],
        "values": [],
        "notifies": 2
      },
      {
        "tag": "SVC-06",
        "steps": [["set", "a", "item"], ["set", "a", "item"]],
        "owners": ["a"],
        "values": ["item"],
        "notifies": 1
      },
      {
        "tag": "SVC-07",
        "steps": [["set", "a", "item"], ["set", "a", "other item"]],
        "owners": ["a"],
        "values": ["other item"],
        "notifies": 2
      },
      {
        "tag": "SVC-08",
        "steps": [["set", "a"]],
        "owners": ["a"],
        "values": [true],
        "notifies": 1
      },
      {
        "tag": "SVC-09",
        "steps": [["set", "b", 1], ["set", "a", 1]],
        "owners": ["b", "a"],
        "values": [1, 1],
        "notifies": 2
      }
    ];
  }

  function test_steps(data) {
    const registry = _make();
    const owners = {
      "a": root.ownerA,
      "b": root.ownerB,
      "c": root.ownerC
    };
    const items = {
      "item": itemComponent.createObject(root),
      "other item": itemComponent.createObject(root)
    };
    root.notified = 0;
    registry.entriesChanged.connect(() => root.notified++);
    for (const [verb, name, value] of data.steps) {
      if (verb === "drop")
        registry.drop(owners[name]);
      else if (value === undefined)
        registry.set(owners[name]);
      else
        registry.set(owners[name], items[value] ?? value);
    }
    compare(registry.entries.map(e => e.owner.name), data.owners);
    compare(registry.values.map(v => typeof v === "object" && v.objectName !== undefined ? Object.keys(items).find(k => items[k] === v) : v), data.values);
    compare(registry.active, data.owners.length > 0);
    compare(root.notified, data.notifies);
  }

  function test_dropped_owner_holds_nothing() {
    const registry = _make();
    registry.set(root.ownerA, 1);
    compare(registry.valueOf(root.ownerA), 1);
    registry.drop(root.ownerA);
    compare(registry.valueOf(root.ownerA), undefined);
    compare(registry.active, false);
  }

  function test_omitted_value_is_true() {
    const registry = _make();
    registry.set(root.ownerA);
    verify(registry.valueOf(root.ownerA) === true);
  }

  function _make() {
    const component = Qt.createComponent(Qt.resolvedUrl("../qml/services/core/OwnerRegistry.qml"));
    compare(component.status, Component.Ready, component.errorString());
    const registry = createTemporaryObject(component, root);
    verify(registry);
    return registry;
  }
}
