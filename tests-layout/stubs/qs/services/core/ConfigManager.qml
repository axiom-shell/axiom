pragma Singleton
import QtQuick

// Stand-in for the shell's ConfigManager in the layout harness: the readers
// (Widget, Appearance) read `live`, which a test sets whole, so every reader
// binding re-runs.
QtObject {
  property var live: ({
      "Interface": {
        "contentSize": 100,
        "cardSize": 100,
        "density": "normal"
      },
      "Appearance": {
        "font": {
          "size": 14,
          "family": "DejaVu Sans Mono"
        },
        "wallpaper": {
          "folder": ""
        }
      }
    })
  property string configDir: ""
}
