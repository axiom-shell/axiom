import QtQuick

// Reads repo files for the tests, by path from the repo root. Needs
// QML_XHR_ALLOW_FILE_READ, which scripts/run_tests.sh sets; the shell itself
// reads files through FileManager instead.
QtObject {
  function url(path) {
    return Qt.resolvedUrl("../" + path);
  }

  function text(path) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url(path), false);
    xhr.send();
    if (xhr.responseText === "")
      throw new Error("empty or unreadable: " + path);
    return xhr.responseText;
  }

  function json(path) {
    return JSON.parse(text(path));
  }
}
