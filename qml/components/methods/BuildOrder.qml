pragma Singleton
import QtQuick

// The order BuildQueueManager builds in: queued order, a `first` entry ahead
// of every other (behind the `first` ones already waiting), and among the
// rest those whose owner is visible before the hidden ones.
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

  // The entry to build next: a `first` one, else the first whose owner is
  // visible, else the first
  function next(queue) {
    if (queue.length > 0 && queue[0].first)
      return queue[0];
    const shown = queue.findIndex(entry => entry.owner?.visible === true);
    return queue[Math.max(0, shown)];
  }
}
