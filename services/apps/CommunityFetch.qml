pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// One run of scripts/community_fetch.sh, for CommunitySetupsManager: its
// output is handed to `done` once it ends. A script that couldn't start
// gives "" (Quickshell then sends neither streamFinished nor exited, only
// `running` going false), which the caller counts as a failure. Not a
// singleton: one per kind of download.
Process {
  id: root

  property bool _started: false

  signal done(string output)

  function launch(args) {
    root._started = false;
    root.command = args;
    root.running = true;
  }

  onStarted: root._started = true
  onRunningChanged: if (!root.running && !root._started)
    root.done("")

  stdout: StdioCollector {
    onStreamFinished: root.done(text)
  }
}
