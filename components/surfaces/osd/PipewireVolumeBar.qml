pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.system
import qs.components.reusable

// A StyledVolumeBar bound to a Pipewire stream (by app name) or the system
// volume: shows and sets its level and mute; the OSD's audio bars.
Item {
  id: root

  // The level changed by the user (not a stream appearing or a device
  // switch): an OSD opens on it
  signal poked

  // -- Public API --
  // Substrings of the app streams to control, in priority order: the bar
  // shows the first matching stream (by the first app with one) and a
  // change sets every matching stream
  property var targetApps: []
  // Instead the first stream that no excludedApps entry matches
  property bool otherApps: false
  property var excludedApps: []
  property bool useSystemVolume: false
  property alias orientation: bar.orientation
  property alias iconSource: bar.iconSource
  property alias showPercent: bar.showPercent
  property alias scrollStep: bar.scrollStep

  readonly property bool nodeFound: !useSystemVolume && _targetNode !== null && _targetNode.ready && _targetNode.audio
  property real volume: useSystemVolume ? AudioManager.volume : (nodeFound ? _targetNode.audio.volume : 0.0)
  property bool isMuted: useSystemVolume ? AudioManager.muted : (!nodeFound || _targetNode.audio.muted)

  // -- Implementation --
  implicitWidth: bar.implicitWidth
  implicitHeight: bar.implicitHeight

  // Every stream being controlled; _targetNode (the first) is the one
  // shown. A binding: matchStreams reads every stream's ready, audio and
  // properties, so it follows streams coming, going and binding
  readonly property var _targetNodes: useSystemVolume ? [] : AudioManager.matchStreams(targetApps, otherApps, excludedApps)
  readonly property var _targetNode: _targetNodes.length > 0 ? _targetNodes[0] : null
  // The controlled streams and their levels, so a change on any of them
  // shows the bar; _nodeKey tells a level change from the set of streams
  // changing
  readonly property string _levels: _keyOf(_targetNodes) + "|" + _targetNodes.map(n => n.audio ? `${n.audio.volume}:${n.audio.muted}` : "").join(",")
  property string _nodeKey: ""
  // The output device the system volume last read: a change as it
  // switches (or binds) is the device's, not the user's
  property var _sink: null

  StyledVolumeBar {
    id: bar
    anchors.fill: parent
    volumeLevel: root.volume
    isMuted: root.isMuted
    enabled: root.nodeFound || root.useSystemVolume
    iconClickable: true
    // I18n.tr("Mute") I18n.tr("Unmute")
    iconTip: root.isMuted ? I18n.tr("Unmute") : I18n.tr("Mute")
    onVolumeChanged: newVolume => root.setVolume(newVolume)
    onIconClicked: root.toggleMute()
  }

  function toggleMute() {
    if (useSystemVolume)
      AudioManager.toggleMute();
    else
      AudioManager.setNodesMuted(_targetNodes, !root.isMuted);
  }

  function _systemChanged() {
    if (!root.useSystemVolume)
      return;
    if (AudioManager.defaultSink === root._sink)
      root.poked();
    root._sink = AudioManager.defaultSink;
  }

  onVolumeChanged: root._systemChanged()
  onIsMutedChanged: root._systemChanged()

  // A device switching to one at the same level and mute changes neither:
  // take it in once the switch's own changes are through
  Connections {
    target: AudioManager
    function onDefaultSinkChanged() {
      Qt.callLater(() => root._sink = AudioManager.defaultSink);
    }
  }

  on_LevelsChanged: {
    const key = root._keyOf(root._targetNodes);
    if (key === root._nodeKey)
      root.poked();
    root._nodeKey = key;
  }

  Component.onCompleted: {
    root._sink = AudioManager.defaultSink;
    root._nodeKey = root._keyOf(root._targetNodes);
  }

  function setVolume(newVolume) {
    if (useSystemVolume)
      AudioManager.setVolume(newVolume);
    else
      AudioManager.setNodesVolume(_targetNodes, newVolume);
  }

  function _keyOf(nodes) {
    return nodes.map(n => n.id).join(",");
  }
}
