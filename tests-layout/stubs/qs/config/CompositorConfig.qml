pragma Singleton
import QtQuick

// Stand-in for the shell's CompositorConfig in the layout harness: the
// compositor mode a settings row reads (managed: no detached badge).
QtObject {
  property string mode: "managed"
}
