pragma Singleton
import QtQuick

// The order BuildQueueManager builds in: queued order, a `first` entry ahead
// of every other (behind the `first` ones already waiting), and among the
// rest those whose owner is visible before the hidden ones. An entry whose
// holder (the nearest ancestor of its owner with a `buildHeld`, an overlay
// page) is holding waits, wherever it is in the queue.
QtObject {
  id: root

  // `queue` with `entry` (one with a `first` flag) added: at the end, or for
  // a `first` one after the `first` ones already there
  function enqueue(queue, entry) {
    if (!entry.first)
      return queue.concat([entry]);
    const at = queue.findIndex(queued => !queued.first);
    const out = queue.slice();
    out.splice(at < 0 ? out.length : at, 0, entry);
    return out;
  }

  // The nearest item from `item` up its parents that carries a `buildHeld`
  // (an overlay page), or null
  function holderOf(item) {
    for (let at = item; at; at = at.parent) {
      if ("buildHeld" in at)
        return at;
    }
    return null;
  }

  // How many entries of `queue` aren't held: the jobs that can run
  function runnable(queue) {
    return root._ready(queue).length;
  }

  // The entry to build next: the first `first` one that isn't held, else
  // the first not held whose owner is visible, else the first not held; null
  // when every entry is held
  function next(queue) {
    const ready = root._ready(queue);
    if (ready.length > 0 && ready[0].first)
      return ready[0];
    const shown = ready.findIndex(entry => entry.owner?.visible === true);
    return ready[Math.max(0, shown)] ?? null;
  }

  // -- Private --
  // The entries of `queue` whose holder isn't holding
  function _ready(queue) {
    return queue.filter(entry => entry.holder?.buildHeld !== true);
  }
}
