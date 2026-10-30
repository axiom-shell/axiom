pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.config
import qs.components.methods
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The active player's track. Sized to the track, shrinking (the label
// elides) down to just the icon when the bar is crowded; `layout.size`
// caps it. The popout centres on the widget when it opens and stays put
// while open, so a resize doesn't move it. Its display style draws the
// track's position (fill, pill), scrolls it (ticker) or puts the title
// over the artist (stacked).
ValueStyleWidget {
  id: root

  readonly property string sizePolicy: "elastic"
  readonly property real minimumSize: root.iconLength + root.padding * 2

  // The artist shown before the title, or "" when there's none to show
  readonly property string artist: MediaManager.activePlayer && root.properties.showArtist ? Utils.truncate(MediaManager.trackArtist, root.properties.artistLength, "") : ""

  // The artist icon goes with the state icon, before the label (stacked
  // shows the artist under the title instead)
  icon: (MediaManager.isPlaying ? "music_note" : "pause") + (root.artist && root.style !== "stacked" ? (root.isVertical ? "\n" : " ") + "artist" : "")
  text: !MediaManager.activePlayer ? root.properties.idleText : root.artist ? root.artist + " - " + MediaManager.trackTitle : MediaManager.trackTitle
  ratio: MediaManager.activePlayer && MediaManager.length > 0 ? MediaManager.progress : -1
  styleText: !MediaManager.activePlayer ? root.properties.idleText : root.style === "stacked" ? MediaManager.trackTitle : root.text
  subtext: root.style === "stacked" ? root.artist : ""
  accentColor: Theme.resolveColor(MediaManager.isPlaying ? root.properties.playingColor : root.properties.pausedColor)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "NowPlaying"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
    openDelay: 150
  }
}
