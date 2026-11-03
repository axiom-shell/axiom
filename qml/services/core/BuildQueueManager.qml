pragma Singleton
import QtQuick

// Spreads building UI over frames: a page's modules (ModuleGrid.stream)
// and tool pages' sections (StreamedLoader) queue a job each, and the jobs
// run a few per 16 ms step, within a 6 ms budget (at least one a step,
// however long it takes), so showing a page never waits on all of it.
// Jobs run in the order queued, those whose owner is visible first (the
// page shown before its neighbours). A job that alone takes over a frame
// is logged (`--debug`), naming its label.
QtObject {
  id: root

  // Jobs still waiting
  readonly property int pending: root._queue.length

  // Queues `job` (a function building something) for `owner` (an Item;
  // its jobs are dropped when it cancels)
  function request(owner, job, label) {
    root._queue = root._queue.concat([
      {
        "owner": owner,
        "job": job,
        "label": label ?? ""
      }
    ]);
  }

  // Drops `owner`'s jobs not run yet: call it from onDestruction
  function cancel(owner) {
    if (root._queue.some(entry => entry.owner === owner))
      root._queue = root._queue.filter(entry => entry.owner !== owner);
  }

  // -- Private --
  property var _queue: []
  readonly property int _budget: 6

  function _next() {
    const shown = root._queue.findIndex(entry => entry.owner?.visible === true);
    return root._queue[Math.max(0, shown)];
  }

  function _step() {
    const start = Date.now();
    do {
      const entry = root._next();
      const before = Date.now();
      try {
        entry.job();
      } catch (error) {
        console.warn(`BuildQueueManager: ${entry.label || "a job"} failed: ${error}`);
      }
      // Dropped once run, not before: `pending` stays above 0 while the
      // last job builds, so what it makes still streams (BaseView)
      root._queue = root._queue.filter(queued => queued !== entry);
      const took = Date.now() - before;
      if (took > 16)
        console.log(`Built ${entry.label || "a queued job"} in ${took} ms`);
    } while (root._queue.length > 0 && Date.now() - start < root._budget)
  }

  property Timer _timer: Timer {
    interval: 16
    repeat: true
    running: root._queue.length > 0
    onTriggered: root._step()
  }
}
