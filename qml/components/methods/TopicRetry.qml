pragma Singleton
import QtQuick

// What the shell does with axiom's answer to a topic subscribe or
// unsubscribe (BackendManager): only a refusal as `busy` is asked again, a
// limited number of times. No file access, processes or services.
QtObject {
  id: root

  // The step for an answer: `error` is null or { kind, message }, `attempts`
  // the retries the topic has had, `max` how many it gets. Returns
  // { action, attempts }: "done" (answered, counter reset), "ignore" (a
  // lost connection: the next hello subscribes again), "warn" (refused for
  // good: say so once, no retry), "retry" (busy: ask again, `attempts`
  // counted) or "giveUp" (busy once too often)
  function decide(error, attempts, max) {
    if (!error)
      return {
        "action": "done",
        "attempts": 0
      };
    if (error.kind === "unavailable")
      return {
        "action": "ignore",
        "attempts": attempts
      };
    if (error.kind !== "busy")
      return {
        "action": "warn",
        "attempts": 0
      };
    if (attempts >= max)
      return {
        "action": "giveUp",
        "attempts": 0
      };
    return {
      "action": "retry",
      "attempts": attempts + 1
    };
  }
}
