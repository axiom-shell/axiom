import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "TopicGrace"

  // The BackendManager side: acquired, pending and a log of what went out
  function sim() {
    return {
      "acquired": {},
      "pending": {},
      "sent": [],
      "acquire": function (topic) {
        this.acquired[topic] = {};
      },
      "release": function (topic, now) {
        if (!(topic in this.acquired))
          return;
        delete this.acquired[topic];
        this.pending = TopicGrace.release(this.pending, topic, now, 1500);
      },
      "fire": function (now) {
        const r = TopicGrace.due(this.pending, this.acquired, now);
        this.pending = r.pending;
        r.unsubscribe.forEach(t => this.sent.push(t));
        return r;
      }
    };
  }

  function test_releaseThenAcquireSendsNothing() {
    const s = sim();
    s.acquire("system");
    s.release("system", 0);
    s.acquire("system");
    s.fire(1500);
    compare(s.sent, []);
    compare(s.pending, {}, "the entry is gone once handled");
  }

  function test_releaseAloneSendsOnce() {
    const s = sim();
    s.acquire("system");
    s.release("system", 0);
    const early = s.fire(1000);
    compare(s.sent, [], "not before the grace period");
    compare(early.wait, 500);
    s.fire(1500);
    compare(s.sent, ["system"]);
    s.fire(3000);
    compare(s.sent, ["system"], "only once");
  }

  function test_releaseAcquireReleaseSendsOnce() {
    const s = sim();
    s.acquire("system");
    s.release("system", 0);
    s.acquire("system");
    s.release("system", 1000);
    s.fire(1500);
    compare(s.sent, [], "the second release has its own grace period");
    s.fire(2500);
    compare(s.sent, ["system"]);
  }

  function test_topicsAreIndependent() {
    const s = sim();
    s.acquire("a");
    s.acquire("b");
    s.release("a", 0);
    s.release("b", 1000);
    s.fire(1500);
    compare(s.sent, ["a"]);
    const r = s.fire(2500);
    compare(s.sent, ["a", "b"]);
    compare(r.wait, -1);
  }

  function test_eachTopicAtItsOwnDeadline() {
    const s = sim();
    s.acquire("a");
    s.acquire("b");
    s.release("a", 0);
    s.release("b", 1000);
    compare(TopicGrace.wait(s.pending, 1000), 500, "the timer waits for the earliest");
    s.fire(1500);
    compare(s.sent, ["a"], "a at its own deadline");
    compare(TopicGrace.wait(s.pending, 1500), 1000, "then b's remaining time");
    s.fire(2499);
    compare(s.sent, ["a"]);
    s.fire(2500);
    compare(s.sent, ["a", "b"], "b at 2500, not later");
  }

  function test_waitWithNothingPending() {
    compare(TopicGrace.wait({}, 0), -1);
  }
}
