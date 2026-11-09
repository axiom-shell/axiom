pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.reusable
import qs.components.surfaces.osd.design

// Now playing's card on the OSD (an OSDCard, loaded by URL as its
// `exposes` entry's `design`): the cover (CoverArt), the title and
// artist, and whether it plays or is paused. Reads MediaManager as it is.
OSDCard {
  title: MediaManager.trackTitle
  subtitle: MediaManager.trackArtist || MediaManager.identity
  // What it's doing, not a button
  status: MediaManager.isPlaying ? "play_arrow" : "pause"

  picture: CoverArt {
    source: MediaManager.artSource
  }
}
