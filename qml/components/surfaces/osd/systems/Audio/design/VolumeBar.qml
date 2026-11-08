pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable

// One of Audio's level bars on the OSD (its exposes entry's `design`,
// loaded by URL): a StyledVolumeBar bound to what its bar shows and sets,
//   master:     the default output's volume
//   other:      the first playing stream no App bar matches
//   app:        the streams its apps match by name (the first shown, all set)
//   microphone: the default input's volume
// its icon a click on which mutes it. Whether a change opens the OSD is
// AudioWatch's; this only draws and sets (was PipewireVolumeBar and
// OSDBar's microphone bar)
Item {
  id: root

  // Its `exposes` entry ({ key, icon, bar: its item in Audio's `bars`:
  // { type, apps, icon, showOsd } })
  property var entry: ({})
  // Its system (an OSDSystemHost: its watcher matches a stream bar's
  // streams, AudioWatch.streamsOf)
  property var system: null
  // The OSD's bar layout: bars run vertically, levels shown as numbers
  property int orientation: Qt.Vertical
  property bool showPercent: true

  readonly property string type: root.entry?.bar?.type ?? ""
  readonly property bool isMaster: root.type === "master"
  readonly property bool isMic: root.type === "microphone"
  readonly property bool isStreams: root.type === "other" || root.type === "app"

  // A stream bar's streams: the first one shown, a change setting every
  // one (a binding: matchStreams reads every stream's ready, volumes and
  // properties, so it follows streams coming, going and binding; each one
  // it returns is bound, its volume in)
  readonly property var _nodes: root.isStreams && root.system?.watch ? root.system.watch.streamsOf(root.entry.bar) : []
  readonly property var _node: root._nodes.length > 0 ? root._nodes[0] : null
  readonly property bool _found: root._node !== null

  readonly property real level: root.isMaster ? AudioManager.volume : root.isMic ? AudioManager.sourceVolume : (root._found ? root._node.audio.volume : 0)
  readonly property bool muted: root.isMaster ? AudioManager.muted : root.isMic ? AudioManager.sourceMuted : (!root._found || root._node.audio.muted)

  implicitWidth: bar.implicitWidth
  implicitHeight: bar.implicitHeight

  StyledVolumeBar {
    id: bar
    anchors.fill: parent
    orientation: root.orientation
    showPercent: root.showPercent
    scrollStep: OSDConfig.scrollStep
    volumeLevel: root.level
    isMuted: root.muted
    enabled: root.isMaster || (root.isMic ? AudioManager.defaultSource !== null : root._found)
    iconSource: root.entry?.bar?.icon || (root.isMaster ? AudioManager.outputIcon(AudioManager.deviceKind(AudioManager.defaultSink), false, Math.max(AudioManager.volume, 0.01)) : root.isMic ? AudioManager.inputIcon(AudioManager.deviceKind(AudioManager.defaultSource), false) : "")
    iconClickable: true
    iconTip: root.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
    onVolumeChanged: newVolume => root.setVolume(newVolume)
    onIconClicked: root.toggleMute()
  }

  function setVolume(newVolume) {
    if (root.isMaster)
      AudioManager.setVolume(newVolume);
    else if (root.isMic)
      AudioManager.setSourceVolume(newVolume);
    else
      AudioManager.setNodesVolume(root._nodes, newVolume);
  }

  function toggleMute() {
    // (marked as the pointer's, so another OSD listing Audio stays shut)
    if (root.isMaster)
      ActionsManager.run("toggleMute", {
        "fromScreen": true
      });
    else if (root.isMic)
      ActionsManager.run("toggleMicMute", {
        "fromScreen": true
      });
    else
      AudioManager.setNodesMuted(root._nodes, !root.muted);
  }
}
