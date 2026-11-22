pragma ComponentBehavior: Bound
import QtQuick

// `model`: a ListModel of `key` rows (strings), kept to `keys` by
// adding and removing rows rather than resetting it, so a Repeater over
// it keeps the items whose keys stay
QtObject {
  id: keyed
  required property var keys
  readonly property ListModel model: ListModel {}

  function sync() {
    const wanted = keyed.keys.map(key => String(key));
    for (let i = keyed.model.count - 1; i >= 0; i--) {
      if (!wanted.includes(keyed.model.get(i).key))
        keyed.model.remove(i);
    }
    const have = [];
    for (let i = 0; i < keyed.model.count; i++)
      have.push(keyed.model.get(i).key);
    for (const key of wanted) {
      if (!have.includes(key))
        keyed.model.append({
          "key": key
        });
    }
  }
  onKeysChanged: keyed.sync()
  Component.onCompleted: keyed.sync()
}
