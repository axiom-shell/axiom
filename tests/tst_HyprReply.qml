import QtQuick
import QtTest
import qs.components.methods

// HyprReply: building a batch, splitting its replies, parsing a reply.
TestCase {
  name: "HyprReply"

  function test_batch() {
    compare(HyprReply.batch(["j/getoption general:gaps_out", "j/animations"]), "[[BATCH]]j/getoption general:gaps_out;j/animations");
  }

  function test_splitBatch() {
    compare(HyprReply.splitBatch("a\n\n\nb", 3), ["a", "b", ""], "a missing reply is empty");
  }

  function test_parse() {
    compare(HyprReply.parse("{\"x\": 1}"), {
      "x": 1
    });
    compare(HyprReply.parse("error: no such option"), null);
  }
}
