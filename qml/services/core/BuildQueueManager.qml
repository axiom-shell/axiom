pragma Singleton
import QtQuick
import qs.components.methods

// Spreads building UI over frames: a page's modules (ModuleGrid.stream)
// and tool pages' sections (StreamedLoader) queue a job each, and the jobs
// run a few per 16 ms step, within a 12 ms budget (at least one a step,
// however long it takes), so showing a page never waits on all of it.
// Jobs run in the order queued, those whose owner is visible first (the
// page shown before its neighbours); a `first` job (the settings sidebar)
// goes ahead of all of them, in the order the first ones were queued. A job
// that alone takes over a frame is logged (`--debug`), naming its label.
// Jobs of an owner on an overlay page that isn't current, or while the
// overlay is closed, wait (BuildOrder.holderOf: the page's `buildHeld`).
QtObject {
  id: root

  // Jobs that can run now: queued and not held (BuildOrder.runnable; tracks
  // each holder's `buildHeld`)
  readonly property int pending: BuildOrder.runnable(root._queue)

  // Queues `job` (a function building something) for `owner` (an Item;
  // its jobs are dropped when it cancels). `first` puts it ahead of every
  // job that isn't, behind the `first` ones already waiting.
  function request(owner, job, label, first) {
    const entry = {
      "owner": owner,
      "job": job,
      "label": label ?? "",
      "first": first === true,
      "holder": BuildOrder.holderOf(owner)
    };
    root._queue = BuildOrder.enqueue(root._queue, entry);
  }

  // Drops `owner`'s jobs not run yet: call it from onDestruction
  function cancel(owner) {
    if (root._queue.some(entry => entry.owner === owner))
      root._queue = root._queue.filter(entry => entry.owner !== owner);
  }

  // -- Private --
  property var _queue: []
  readonly property int _budget: 12

  function _next() {
    return BuildOrder.next(root._queue);
  }

  function _step() {
    const start = Date.now();
    for (let entry = root._next(); entry !== null; entry = root._next()) {
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
      if (Date.now() - start >= root._budget)
        return;
    }
  }

  property Timer _timer: Timer {
    interval: 16
    repeat: true
    running: root.pending > 0
    onTriggered: root._step()
  }
}
