pragma Singleton
import QtQuick

// Stand-in for the shell's FileSearchManager in the layout harness: no file
// has a thumbnail.
QtObject {
  property var thumbnails: ({})

  function thumbnailKey(path, mtime) {
    return "";
  }

  function want(key, path) {
  }

  function unwant(key) {
  }
}
