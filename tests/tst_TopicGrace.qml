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
}
