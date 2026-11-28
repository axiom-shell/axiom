import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "WriteQueue"

  function test_push_to_empty() {
    const done = () => 1;
    const queue = WriteQueue.push([], "a", done);
    compare(queue.length, 1);
    compare(queue[0].text, "a");
    compare(queue[0].dones.length, 1);
    verify(queue[0].dones[0] === done);
  }

  function test_push_without_done() {
    const queue = WriteQueue.push([], "a");
    compare(queue[0].dones, []);
  }

  function test_push_collapses() {
    const queue = [];
    WriteQueue.push(queue, "a");
    WriteQueue.push(queue, "b");
    WriteQueue.push(queue, "c");
    compare(queue.length, 1, "one entry");
    compare(queue[0].text, "c", "the newest text");
  }

  function test_later_done_added() {
    const queue = [];
    const done = () => 1;
    WriteQueue.push(queue, "a");
    WriteQueue.push(queue, "b", done);
    compare(queue.length, 1);
    compare(queue[0].text, "b");
    compare(queue[0].dones.length, 1);
    verify(queue[0].dones[0] === done);
  }

  function test_dones_keep_order() {
    const queue = [];
    const first = () => 1;
    const second = () => 2;
    WriteQueue.push(queue, "a", first);
    WriteQueue.push(queue, "b");
    WriteQueue.push(queue, "c", second);
    verify(queue[0].dones[0] === first);
    verify(queue[0].dones[1] === second);
    compare(queue[0].dones.length, 2);
  }

  function test_next() {
    const queue = WriteQueue.push([], "a");
    compare(WriteQueue.next(queue).text, "a");
    compare(queue.length, 0);
    compare(WriteQueue.next(queue), null, "empty");
  }
}
