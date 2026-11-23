pragma ComponentBehavior: Bound
import QtQuick

// `model`: a ListModel of `key` rows (strings), kept to `keys` by
// adding and removing rows rather than resetting it, so a Repeater over
// it keeps the items whose keys stay
QtObject {
  id: root
  required property var keys
  readonly property ListModel model: ListModel {}

  function sync() {
    const wanted = root.keys.map(key => String(key));
    for (let i = root.model.count - 1; i >= 0; i--) {
      if (!wanted.includes(root.model.get(i).key))
        root.model.remove(i);
    }
    const have = [];
    for (let i = 0; i < root.model.count; i++)
      have.push(root.model.get(i).key);
    for (const key of wanted) {
      if (!have.includes(key))
        root.model.append({
          "key": key
        });
    }
  }
  onKeysChanged: root.sync()
  Component.onCompleted: root.sync()
}
