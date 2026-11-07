pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Now playing's state for the OSD: the active player's track (its title
// the value, "" with no active player), its artist, cover and whether it
// plays
OSDWatch {
  state: ({
      "media": {
        "value": MediaManager.hasActivePlayer ? MediaManager.trackTitle : "",
        "player": MediaManager.identity,
        "title": MediaManager.trackTitle,
        "artist": MediaManager.trackArtist,
        "playing": MediaManager.isPlaying,
        "art": MediaManager.artSource
      }
    })
}
