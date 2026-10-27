pragma Singleton
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core

// The todo list: one list for every widget and module, kept in
// $XDG_DATA_HOME/axiom/todo.json ({ version, items }: TodoItems' shape),
// written atomically and watched through axiom (FileManager), so an edit
// made elsewhere shows at once.
// While the file can't be read (a hand edit half done), nothing is written
// over it. Never read or written in the greeter.
//
//   axiom ipc todo add "Buy milk"
QtObject {
  id: root

  // Every item, in order (see TodoItems)
  readonly property var items: root._items
  readonly property int openCount: TodoItems.openCount(root._items)
  readonly property bool loaded: root._loaded
  readonly property string path: Paths.userDataPath + "todo.json"

  // What a list shows (TodoItems.shown, with Todo.showCompleted)
  readonly property var shownItems: TodoItems.shown(root._items, TodoConfig.showCompleted)

  // Adds an open item; its uid, or "" for an empty text (or a list that
  // can't be written now)
  function add(text) {
    const uid = root._newUid();
    return root._set(TodoItems.add(root._items, text, Date.now(), uid)) ? uid : "";
  }

  // Done ↔ open (`done` given: sets it)
  function toggle(uid, done) {
    root._set(TodoItems.toggle(root._items, uid, Date.now(), done));
  }

  function rename(uid, text) {
    root._set(TodoItems.rename(root._items, uid, text));
  }

  function remove(uid) {
    root._set(TodoItems.remove(root._items, uid));
  }

  // To `index` in `items`
  function move(uid, index) {
    root._set(TodoItems.move(root._items, uid, index));
  }

  function clearCompleted() {
    root._set(TodoItems.clearCompleted(root._items));
  }

  function find(uid) {
    return TodoItems.find(root._items, uid);
  }

  // -- Private --

  property var _items: []
  property bool _loaded: false
  // The file holds something that isn't a list: left alone until fixed
  property bool _unreadable: false
  property var _watch: null
  property int _serial: 0

  function _newUid() {
    root._serial += 1;
    return Date.now().toString(36) + "-" + Math.floor(Math.random() * 0xffffff).toString(36) + "-" + root._serial;
  }

  // Shows and writes `items`; false when nothing changed or it can't be
  // written
  function _set(items) {
    if (Paths.greeter || !root._loaded || items === root._items)
      return false;
    if (root._unreadable) {
      console.warn("[TodoManager] Not saving over", root.path, "until it's valid JSON again");
      return false;
    }
    root._items = items;
    root._write();
    return true;
  }

  function _write() {
    FileManager.write(root.path, JSON.stringify({
      "version": 1,
      "items": root._items
    }, null, 2) + "\n");
  }

  // Nothing saved yet: an empty list
  function _load() {
    const text = FileManager.read(root.path);
    if (text === null)
      root._loaded = true;
    else
      root._parse(text);
  }

  function _parse(text) {
    try {
      const data = JSON.parse(text);
      root._items = TodoItems.normalize(data?.items);
      root._unreadable = false;
    } catch (e) {
      root._unreadable = true;
      console.warn("[TodoManager] Couldn't read", root.path + ":", e.message, "(keeping the list shown, and not saving over it)");
    }
    root._loaded = true;
  }

  Component.onCompleted: {
    if (Paths.greeter)
      return;
    root._load();
    root._watch = FileManager.watch(root.path, () => root._load());
  }

  Component.onDestruction: FileManager.unwatch(root._watch)

  property IpcTarget _ipc: IpcTarget {
    target: "todo"
    enabled: !Paths.greeter

    // Adds an item; false for an empty text
    function add(text: string): bool {
      return root.add(text) !== "";
    }

    // The open items, one per line
    function list(): string {
      return TodoItems.shown(root._items, false).map(item => item.summary).join("\n");
    }

    // Ticks off (or reopens) the first item whose text is `text`
    function toggle(text: string): bool {
      const item = root._items.find(entry => entry.summary === text.trim());
      if (!item)
        return false;
      root.toggle(item.uid);
      return true;
    }

    function clearCompleted(): void {
      root.clearCompleted();
    }

    function count(): int {
      return root.openCount;
    }
  }
}
