pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.reusable
import Quickshell.Services.Pipewire

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

  // Every stream being controlled; _targetNode (the first) is the one shown
  property var _targetNodes: []
  readonly property var _targetNode: _targetNodes.length > 0 ? _targetNodes[0] : null
  // The controlled streams' levels, so a change on any of them shows the
  // bar; _nodeKey tells a level change from the set of streams changing
  readonly property string _levels: _targetNodes.map(n => n.audio ? `${n.audio.volume}:${n.audio.muted}` : "").join(",")
  property string _nodeKey: ""

  // Every playback stream (not recording ones: an app's mic capture shares
  // its name). AudioManager tracks them all (which binds them, so their
  // .properties are there to search), but binding is async
  readonly property var _audioStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)

  // Re-run the search whenever a candidate finishes binding (node.ready
  // flips true): tracking only *requests* a bind
  Instantiator {
    model: root._audioStreams
    delegate: Item {
      id: streamWatcher
      required property var modelData
      Connections {
        target: streamWatcher.modelData
        function onReadyChanged() {
          if (streamWatcher.modelData.ready) {
            root._updateTargetNode();
          }
        }
      }
    }
  }

  StyledVolumeBar {
    id: bar
    anchors.fill: parent
    volumeLevel: root.volume
    isMuted: root.isMuted
    enabled: root.nodeFound || root.useSystemVolume
    onVolumeChanged: newVolume => root.setVolume(newVolume)
  }

  onVolumeChanged: {
    if (root.useSystemVolume)
      root.poked();
  }
  onIsMutedChanged: {
    if (root.useSystemVolume)
      root.poked();
  }

  on_LevelsChanged: {
    const key = root._keyOf(root._targetNodes);
    if (key === root._nodeKey)
      root.poked();
    root._nodeKey = key;
  }

  function setVolume(newVolume) {
    if (useSystemVolume)
      AudioManager.setVolume(newVolume);
    else
      AudioManager.setNodesVolume(_targetNodes, newVolume);
  }

  function toggleMute() {
    if (useSystemVolume)
      AudioManager.toggleMute();
    else if (nodeFound)
      AudioManager.setNodesMuted(_targetNodes, !_targetNode.audio.muted);
  }

  // Config changes (a reload, another saved config) pick the stream again
  onTargetAppsChanged: _updateTargetNode()
  onOtherAppsChanged: {
    if (Pipewire.ready)
      _updateTargetNode();
  }
  onExcludedAppsChanged: {
    if (Pipewire.ready)
      _updateTargetNode();
  }
  onUseSystemVolumeChanged: {
    if (Pipewire.ready)
      _updateTargetNode();
  }

  Component.onCompleted: {
    if (Pipewire.ready) {
      _updateTargetNode();
    }
  }

  Connections {
    target: Pipewire.nodes
    function onObjectInsertedPost(object, index) {
      if (Pipewire.ready) {
        root._updateTargetNode();
      }
    }
    function onObjectRemovedPost(object, index) {
      if (Pipewire.ready) {
        root._updateTargetNode();
      }
    }
  }

  Connections {
    target: Pipewire
    function onReadyChanged() {
      if (Pipewire.ready) {
        root._updateTargetNode();
      }
    }
  }

  function _keyOf(nodes) {
    return nodes.map(n => n.id).join(",");
  }

  function _setTargetNodes(nodes) {
    const key = _keyOf(nodes);
    if (key === _keyOf(_targetNodes))
      return;
    // on_LevelsChanged sees the new key and doesn't count this as a change;
    // set it again in case the levels read the same
    _targetNodes = nodes;
    _nodeKey = key;
  }

  function _updateTargetNode() {
    _setTargetNodes(useSystemVolume ? [] : AudioManager.matchStreams(targetApps, otherApps, excludedApps));
  }
}
