pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The active player's track. Sized to the track, shrinking (the label
// elides) down to just the icon (after the fill style's meter) when the bar
// is crowded; `layout.maxSize` caps it. The popout centres on the widget
// when it opens and stays put while open, so a resize doesn't move it. Its
// display style draws the track's position (fill, pill), scrolls it
// (ticker) or puts the title over the artist (stacked).
BarWidget {
  id: root

  // The artist shown before the title, or "" when there's none to show
  readonly property string artist: MediaManager.activePlayer && root.properties.showArtist ? Utils.truncate(MediaManager.trackArtist, root.properties.artistLength, "") : ""

  // What it says when nothing plays: the text set, else the translated default
  readonly property string _idleText: root.properties.idleText !== "" ? root.properties.idleText : I18n.tr("No player")

  // The artist icon goes with the state icon, before the label (stacked
  // shows the artist under the title instead)
  icon: (MediaManager.isPlaying ? "music_note" : "pause") + (root.artist && root.valueStyle !== "stacked" ? "\nartist" : "")
  text: !MediaManager.activePlayer ? root._idleText : root.artist ? root.artist + " - " + MediaManager.trackTitle : MediaManager.trackTitle
  ratio: MediaManager.activePlayer && MediaManager.length > 0 ? MediaManager.progress : -1
  styleText: !MediaManager.activePlayer ? root._idleText : root.valueStyle === "stacked" ? MediaManager.trackTitle : root.text
  subtext: root.valueStyle === "stacked" ? root.artist : ""
  // A track title is any player's: never styled text or a remote image
  textFormat: Text.PlainText
  accentField: MediaManager.isPlaying ? "playingColor" : "pausedColor"

  // News: the track changed while playing (a player appearing, its first
  // track, isn't). Set once at start and by the handler only: as a
  // binding it could take the new title before the handler reads it
  property string _lastTitle: ""
  Connections {
    target: MediaManager
    function onTrackTitleChanged() {
      if (MediaManager.isPlaying && root._lastTitle !== "" && MediaManager.trackTitle !== "")
        root.attention();
      root._lastTitle = MediaManager.trackTitle;
    }
  }

  Component.onCompleted: {
    root._lastTitle = MediaManager.trackTitle;
    MediaManager.acquire(root);
  }
  Component.onDestruction: MediaManager.release(root)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "NowPlaying"
    active: MenusConfig.opensOwnPopout(root.properties)
    openDelay: 150
  }
}
