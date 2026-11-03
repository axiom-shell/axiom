pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.reusable

// An OSD's now playing card (an OSDCard): the cover (CoverArt), the title
// and artist, and whether it plays or is paused. Reads MediaManager as it
// is; OSDStatusSource says when to show it.
OSDCard {
  title: MediaManager.trackTitle
  subtitle: MediaManager.trackArtist || MediaManager.identity
  // What it's doing, not a button
  status: MediaManager.isPlaying ? "play_arrow" : "pause"

  picture: CoverArt {
    source: MediaManager.artSource
  }
}
