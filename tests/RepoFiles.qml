import QtQuick

// Reads repo files for the tests, by path from the repo root. Needs
// QML_XHR_ALLOW_FILE_READ, which scripts/run_tests.sh sets; the shell itself
// reads files through FileManager instead. recording(kind) tells a test
// whether scripts/dev/fixtures.py is recording that kind (tests/.recording).
QtObject {
  function url(path) {
    return Qt.resolvedUrl("../" + path);
  }

  function _read(path) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url(path), false);
    xhr.send();
    return xhr.responseText;
  }

  function text(path) {
    const content = _read(path);
    if (content === "")
      throw new Error("empty or unreadable: " + path);
    return content;
  }

  function recording(kind) {
    return _read("tests/.recording").replace(/\n$/, "") === kind;
  }

  function json(path) {
    return JSON.parse(text(path));
  }
}
