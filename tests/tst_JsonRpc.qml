import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "JsonRpc"

  function test_frames_one_line_each() {
    const r = JsonRpc.request(3, "config.get");
    compare(r, '{"jsonrpc":"2.0","id":3,"method":"config.get"}\n');
    compare(JsonRpc.result(7, undefined), '{"jsonrpc":"2.0","id":7,"result":null}\n');
    verify(!JsonRpc.request(1, "x", {
      "text": "a\nb"
    }).slice(0, -1).includes("\n"), "a newline in a value stays escaped");
  }

  function test_parses_each_kind() {
    compare(JsonRpc.parse('{"jsonrpc":"2.0","id":1,"result":{"a":1}}').result.a, 1);
    compare(JsonRpc.parse('{"jsonrpc":"2.0","method":"config.changed","params":{"revision":2}}').kind, "notification");
    const req = JsonRpc.parse('{"jsonrpc":"2.0","id":"9","method":"ipc.call","params":{}}');
    compare(req.kind, "request");
    compare(req.id, "9");
    const err = JsonRpc.parse('{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"bad","data":{"kind":"invalid_config","issues":[{"path":"a","message":"b"}]}}}');
    compare(err.error.kind, "invalid_config");
    compare(err.error.issues.length, 1);
    compare(JsonRpc.parse('{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"no"}}').error.kind, "internal");
    compare(JsonRpc.parse("nope").kind, "invalid");
    compare(JsonRpc.parse('{"id":1,"result":1}').kind, "invalid");
    compare(JsonRpc.parse('[1]').kind, "invalid");
  }
}
