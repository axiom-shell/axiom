import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "HookupStatus"

  readonly property var doneRow: ({
      "done": true,
      "conflicts": []
    })
  readonly property var todoRow: ({
      "done": false,
      "conflicts": []
    })

  function test_off() {
    compare(HookupStatus.of(false, [doneRow]).state, "off", "off with done targets is still off");
    compare(HookupStatus.of(false, []).word, "Off");
    compare(HookupStatus.of(false, []).tone, "");
  }

  function test_checking() {
    compare(HookupStatus.of(true, []).state, "checking");
    compare(HookupStatus.of(true, undefined).state, "checking");
    compare(HookupStatus.of(true, []).word, "Checking");
  }

  function test_done() {
    const s = HookupStatus.of(true, [doneRow]);
    compare(s.state, "done");
    compare(s.word, "Set up");
    compare(s.tone, "success");
    compare(HookupStatus.of(true, [doneRow,
      {
        "skipped": "requires",
        "conflicts": []
      }
    ]).state, "done", "a skipped target doesn't count");
    verify(HookupStatus.done([doneRow]));
    verify(!HookupStatus.done([]));
  }

  function test_todo() {
    const s = HookupStatus.of(true, [doneRow, todoRow]);
    compare(s.state, "todo");
    compare(s.word, "Not set up");
    compare(s.tone, "warning");
  }

  function test_partial() {
    const s = HookupStatus.of(true, [
      {
        "done": false,
        "conflicts": ["x"]
      }
    ]);
    compare(s.state, "partial");
    compare(s.word, "Not set up");
    compare(s.tone, "");
  }

  function test_copy() {
    compare(HookupStatus.of(true, [
      {
        "copyOnly": true,
        "conflicts": []
      }
    ]).state, "copy");
    const s = HookupStatus.of(true, [
      {
        "skipped": "shell",
        "conflicts": []
      }
    ]);
    compare(s.state, "copy");
    compare(s.word, "Copy the text");
  }
}
