import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "SpecialWorkspaces"

  function test_validId_data() {
    return [
      {
        "tag": "plain",
        "id": "magic",
        "ok": true
      },
      {
        "tag": "dash and underscore",
        "id": "my-pad_2",
        "ok": true
      },
      {
        "tag": "dot",
        "id": "a.b",
        "ok": true
      },
      {
        "tag": "32 chars",
        "id": "a".repeat(32),
        "ok": true
      },
      {
        "tag": "empty",
        "id": "",
        "ok": false
      },
      {
        "tag": "reserved",
        "id": "special",
        "ok": false
      },
      {
        "tag": "leading dash",
        "id": "-x",
        "ok": false
      },
      {
        "tag": "space",
        "id": "my pad",
        "ok": false
      },
      {
        "tag": "semicolon",
        "id": "a;b",
        "ok": false
      },
      {
        "tag": "comma",
        "id": "a,b",
        "ok": false
      },
      {
        "tag": "33 chars",
        "id": "a".repeat(33),
        "ok": false
      },
      {
        "tag": "non-ascii",
        "id": "Ä",
        "ok": false
      },
      {
        "tag": "not a string",
        "id": null,
        "ok": false
      }
    ];
  }

  function test_validId(data) {
    compare(SpecialWorkspaces.validId(data.id), data.ok);
  }
}
