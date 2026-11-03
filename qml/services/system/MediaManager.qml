pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

import qs.config
import qs.components.methods
import qs.services.core

// The active MPRIS player (MediaPick: the one picked with selectPlayer,
// else the one that most recently started playing, else the last active,
// else one that can play) for the media widgets, the lockscreen and the
// media keys: its track, position and controls, and its album art
// downloaded to a local file. `position` ticks only while a display has
// acquire()d it.
QtObject {
  id: root

  property var activePlayer: null

  // --- Properties we can pass through ---
  readonly property bool hasActivePlayer: activePlayer !== null
  readonly property bool isPlaying: playbackState === MprisPlaybackState.Playing
  readonly property int playbackState: activePlayer ? activePlayer.playbackState : MprisPlaybackState.Stopped

  // --- Properties we fully control to be explicit, partially due to a bug with YT Music ---
  property real position: 0
  property real length: 0
  readonly property real progress: length > 0 ? (position / length) : 0

  // --- Everything else ---
  readonly property string identity: activePlayer ? activePlayer.identity : ""
  readonly property string trackTitle: activePlayer ? activePlayer.trackTitle : ""
  readonly property string trackArtist: activePlayer ? activePlayer.trackArtist : ""
  readonly property string artUrl: activePlayer ? activePlayer.trackArtUrl : ""
  readonly property string artFileName: artUrl ? Qt.md5(artUrl) + ".jpg" : ""
  readonly property string artFilePath: artFileName ? Paths.runtimePath + "media-art/" + artFileName : ""
  property bool artDownloaded: false
  // The cover as an image source once downloaded, else "". Each URL has
  // its own file, and a new URL clears artDownloaded first, so a new cover
  // is always a new source
  readonly property string artSource: artDownloaded ? "file://" + artFilePath : ""
  readonly property bool canTogglePlaying: activePlayer ? activePlayer.canTogglePlaying : false
  readonly property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
  readonly property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
  readonly property bool canSeek: activePlayer ? activePlayer.canSeek : false

  // A new track, or another player: whatever art is shown is stale
  onArtUrlChanged: {
    // Reset immediately so the UI falls back to its placeholder rather
    // than briefly showing the previous track's art under the new one.
    root.artDownloaded = false;
    // Coalesced: players often clear the URL and set the new one in quick
    // succession on a track change
    Qt.callLater(root._fetchArt);
  }

  // The URL the running fetch is for; a result for any other URL is stale
  property string _artFetchUrl: ""

  // Built here from the current values (not a binding): bindings on artUrl
  // may not have updated yet inside onArtUrlChanged, which used to start
  // a download with the previous, often empty, URL. axiom fetches it
  // (media.art: downloaded, or copied from a file:// URL, into .part and
  // renamed, so an interrupted one is never mistaken for a cached file;
  // art already there is kept). One at a time: a newer URL is fetched
  // when the running one ends, and one cut off by axiom re-execing goes
  // again once it's back.
  function _fetchArt() {
    const url = root.artUrl;
    if (!url || root._artFetchUrl !== "")
      return;
    root._artFetchUrl = url;
    BackendManager.call("media.art", {
      "url": url,
      "path": root.artFilePath
    }, error => {
      root._artFetchUrl = "";
      // The track moved on while this was fetching: fetch the new one
      if (url !== root.artUrl) {
        Qt.callLater(root._fetchArt);
        return;
      }
      if (!error) {
        console.log("[MediaManager] Album art ready:", root.artFilePath);
        root.artDownloaded = true;
      } else {
        console.warn("[MediaManager] Failed to fetch album art from:", url, error.message);
        root.artDownloaded = false;
      }
    }, {
      "repeatable": true
    });
  }

  // --- Public ---

  function updateAllMetadata() {
    if (!hasActivePlayer) {
      console.log("[MediaManager] No active MPRIS player to update metadata from.");
      return;
    }
    length = activePlayer.length || 0;
    root.updatePosition();
  }

  function updatePosition() {
    if (hasActivePlayer) {
      activePlayer.positionChanged();
      // Potential bug with youtube music AUR package and mpris
      // Simply requires a skip to sync positions
      if (activePlayer.position > length && length > 0) {
        position = activePlayer.position - length;
      } else {
        position = activePlayer.position;
      }
    }
  }

  property Connections _mprisConnections: Connections {
    target: activePlayer
    ignoreUnknownSignals: true
    function onTrackTitleChanged() {
      root.updateAllMetadata();
    }
    // Some players report the length after the title
    function onLengthChanged() {
      root.length = root.activePlayer.length || 0;
    }
  }

  onActivePlayerChanged: {
    if (activePlayer)
      updateAllMetadata();
  }

  function togglePlayPause() {
    if (hasActivePlayer && activePlayer.canTogglePlaying) {
      activePlayer.togglePlaying();
    }
  }

  function next() {
    if (hasActivePlayer && activePlayer.canGoNext) {
      activePlayer.next();
    }
  }

  function previous() {
    if (hasActivePlayer && activePlayer.canGoPrevious) {
      activePlayer.previous();
    }
  }

  function stop() {
    if (hasActivePlayer && activePlayer.canControl) {
      activePlayer.stop();
    }
  }

  // Media keys (keybind actions mediaPlayPause, ...), for the active player
  property IpcTarget _ipc: IpcTarget {
    target: "media"

    function playPause(): void {
      root.togglePlayPause();
    }

    function next(): void {
      root.next();
    }

    function previous(): void {
      root.previous();
    }

    function stop(): void {
      root.stop();
    }
  }

  function setPositionByRatio(ratio) {
    if (canSeek && length > 0) {
      ratio = Math.max(0, Math.min(1, ratio));
      const seekPosition = ratio * length;
      activePlayer.position = seekPosition;
    }
  }

  // Displays of the position (the Media widget, NowPlaying): it ticks only
  // while one holds it
  function acquire(owner) {
    root._registry.acquire(owner, true);
    root.updatePosition();
  }

  function release(owner) {
    root._registry.release(owner);
  }

  // --- Helper Functions ---

  function formatTime(seconds) {
    if (!seconds || seconds < 0)
      return "0:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return mins + ":" + (secs < 10 ? "0" : "") + secs;
  }

  // --- Private Logic, Timers, and Workers ---

  property ConsumerRegistry _registry: ConsumerRegistry {}

  property Timer _positionTimer: Timer {
    running: root.isPlaying && root._registry.active
    interval: 500
    repeat: true
    // Copies the position into `position` too, so every consumer sees it
    // advance (not only ones that call updatePosition themselves)
    onTriggered: root.updatePosition()
  }

  // Players already running at startup or a reload (later ones:
  // onPlayersChanged), seen with no known start, so a later list change
  // doesn't take a playing one for new and drop the pin
  Component.onCompleted: {
    root._startedAt = Object.fromEntries(root.players.map(p => [p.dbusName, 0]));
    root._pick();
  }

  // Every player, for player switchers
  readonly property var players: Mpris.players?.values ?? []
  // The bus name of a player the user picked: kept until it goes away or
  // another starts playing
  property string _pinnedId: ""
  // Bus name -> when it last started playing (ms; 0 unknown), for every
  // player seen playing or present at startup
  property var _startedAt: ({})

  function selectPlayer(player) {
    root._pinnedId = player.dbusName;
    root._pick();
  }

  function _pick() {
    const id = MediaPick.pick(root.players.map(p => ({
          "id": p.dbusName,
          "playing": p.playbackState === MprisPlaybackState.Playing,
          "canPlay": p.canPlay,
          "startedAt": root._startedAt[p.dbusName] ?? 0
        })), root._pinnedId, root.activePlayer?.dbusName ?? "");
    root.activePlayer = root.players.find(p => p.dbusName === id) ?? null;
  }

  // A player that appears already playing (no playbackStateChanged seen)
  // started now, and drops the pin as one starting would; a vanished
  // one's time goes
  onPlayersChanged: {
    if (!root.players.some(p => p.dbusName === root._pinnedId))
      root._pinnedId = "";
    const startedAt = {};
    for (const p of root.players) {
      if (p.dbusName in root._startedAt)
        startedAt[p.dbusName] = root._startedAt[p.dbusName];
      else if (p.playbackState === MprisPlaybackState.Playing) {
        startedAt[p.dbusName] = Date.now();
        root._pinnedId = "";
      }
    }
    root._startedAt = startedAt;
    root._pick();
  }

  // A player starting playback becomes the active one
  property Instantiator _playback: Instantiator {
    model: Mpris.players

    delegate: Connections {
      required property var modelData
      target: modelData

      function onPlaybackStateChanged() {
        if (modelData.playbackState === MprisPlaybackState.Playing) {
          root._startedAt[modelData.dbusName] = Date.now();
          if (root._pinnedId !== modelData.dbusName)
            root._pinnedId = "";
        }
        root._pick();
      }
    }
  }
}
