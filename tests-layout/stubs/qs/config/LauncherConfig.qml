pragma Singleton
import QtQuick

// Stand-in for the shell's LauncherConfig reader in the layout harness: the two
// values a LauncherRow reads.
QtObject {
  property int iconSize: 32
  property bool showDescriptions: true
}
