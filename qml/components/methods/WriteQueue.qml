pragma Singleton
import QtQuick

// The waiting writes of one file: an array of { text, dones } for the
// writes not yet sent (the one in flight is not in it). A write asked
// while others wait replaces the newest one's text, since only the last
// text matters; every caller's done still gets called. No file access,
// processes or services.
QtObject {
  id: root

  // Adds `text` (and `done`, when given) to `queue`, collapsing into the
  // last entry when there is one; returns the queue
  function push(queue, text, done) {
    if (queue.length > 0) {
      const last = queue[queue.length - 1];
      last.text = text;
      if (done)
        last.dones.push(done);
      return queue;
    }
    queue.push({
      "text": text,
      "dones": done ? [done] : []
    });
    return queue;
  }

  // Removes and returns the first entry, or null when none waits
  function next(queue) {
    return queue.length > 0 ? queue.shift() : null;
  }
}
