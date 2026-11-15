pragma Singleton
import QtQuick

// Stand-in for the shell's ThemeManager in the layout harness: the theme and
// its defaults, which a test sets.
QtObject {
  property var currentTheme: ({})
  property var defaults: ({})
}
