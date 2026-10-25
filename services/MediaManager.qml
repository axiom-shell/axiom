pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

import qs.config

// The active MPRIS player (Spotify first, else one playing, else one
// that can play; or the one picked with selectPlayer) for the media
// widgets, the lockscreen and the media keys: its track, position and
// controls, and its album art downloaded to a local file.
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
  // Bumped when new art lands, so images reload the same path
  property int artVersion: 0
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
  // when the running one ends.
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
        root.artVersion++;
      } else {
        console.warn("[MediaManager] Failed to fetch album art from:", url, error.message);
        root.artDownloaded = false;
      }
    });
  }

  // A fetch cut off by axiom restarting is tried again once it's back
  property Connections _backend: Connections {
    target: BackendManager
    function onGreeted() {
      if (!root.artDownloaded)
        root._fetchArt();
    }
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

  // --- Helper Functions ---

  function formatTime(seconds) {
    if (!seconds || seconds < 0)
      return "0:00";
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return mins + ":" + (secs < 10 ? "0" : "") + secs;
  }

  // --- Private Logic, Timers, and Workers ---

  property Timer _positionTimer: Timer {
    running: root.isPlaying && root.hasActivePlayer
    interval: 500
    repeat: true
    // Copies the position into `position` too, so every consumer sees it
    // advance (not only ones that call updatePosition themselves)
    onTriggered: root.updatePosition()
  }

  // Players already running at startup (later ones: onPlayersChanged)
  Component.onCompleted: {
    if (root.players.length > 0) {
      root._updateActivePlayer();
      root.updateAllMetadata();
    }
  }

  function _pickActivePlayer() {
    const playersArray = Mpris.players.values;
    console.log("[MediaManager] Picking active MPRIS player from", playersArray.length, "available players.");
    if (!playersArray || playersArray.length === 0)
      return null;

    const playerCount = playersArray.length;

    for (let i = 0; i < playerCount; ++i) {
      const p = playersArray[i];
      if (p.dbusName && p.dbusName.indexOf("org.mpris.MediaPlayer2.spotify") !== -1) {
        return p;
      }
    }
    for (let i = 0; i < playerCount; ++i) {
      const p = playersArray[i];
      if (p.playbackState === MprisPlaybackState.Playing) {
        return p;
      }
    }
    for (let i = 0; i < playerCount; ++i) {
      const p = playersArray[i];
      if (p.canPlay) {
        return p;
      }
    }
    return playersArray[0];
  }

  function _updateActivePlayer() {
    const newPlayer = _pickActivePlayer();
    if (activePlayer !== newPlayer) {
      activePlayer = newPlayer;
    }
  }

  // Every player, for player switchers
  readonly property var players: Mpris.players?.values ?? []
  // A player the user picked; kept until it goes away
  property var _pinnedPlayer: null

  function selectPlayer(player) {
    root._pinnedPlayer = player;
    root.activePlayer = player;
    updateAllMetadata();
  }

  // Players come and go after startup: keep a pinned player while it
  // exists, otherwise re-pick (and drop a player that has vanished)
  onPlayersChanged: {
    if (root._pinnedPlayer && root.players.includes(root._pinnedPlayer))
      return;
    root._pinnedPlayer = null;
    _updateActivePlayer();
    if (root.activePlayer)
      updateAllMetadata();
  }
}
