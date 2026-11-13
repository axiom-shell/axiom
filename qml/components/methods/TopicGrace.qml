pragma Singleton
import QtQuick

// The bookkeeping of BackendManager's unsubscribe grace period: a topic
// released a moment before someone acquires it again (the bar's widgets
// built, destroyed and rebuilt at shell start) is not unsubscribed, so the
// daemon doesn't stop and restart its fetch loop. `pending` is
// { topic: deadline in ms }, one entry per topic; the caller owns the
// clock and the timer. No timers, files or services.
QtObject {
  id: root

  // `pending` with `topic` due at now + grace (a later release moves it)
  function release(pending, topic, now, grace) {
    const next = Object.assign({}, pending);
    next[topic] = now + grace;
    return next;
  }

  // ms from `now` to the earliest deadline in `pending` (0 when one is
  // past), or -1 with none: how long the caller's timer should wait
  function wait(pending, now) {
    let next = -1;
    for (const topic in pending) {
      const left = Math.max(0, pending[topic] - now);
      next = next < 0 ? left : Math.min(next, left);
    }
    return next;
  }

  // What to do at `now`: { unsubscribe: topics due and still not acquired,
  // pending: the entries not due yet, wait: ms to the next deadline, or -1
  // with none left }. `acquired` is { topic: request }
  function due(pending, acquired, now) {
    const unsubscribe = [];
    const rest = {};
    for (const topic in pending) {
      const deadline = pending[topic];
      if (deadline > now)
        rest[topic] = deadline;
      else if (!(topic in acquired)) {
        unsubscribe.push(topic);
      }
    }
    return {
      "unsubscribe": unsubscribe,
      "pending": rest,
      "wait": root.wait(rest, now)
    };
  }
}
