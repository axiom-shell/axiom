pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Now playing on the OSD: the now playing card (card only), drawn by its
// own design (design/MediaCard: the cover, title, artist, playing or
// paused), on a new track (`onTrackChange`) and optionally on play and
// pause (`onPlayPause`); never with no player or no title. The card an OSD
// with no bars or icons opens on (`preview`). Declared: the track (its
// title while a player is active) is the value, so a new one is an add or
// a change and losing it nothing; playing is its look (`on`), so play and
// pause are an update; the artist and the cover filling in are neither
// (MediaWatch reads MediaManager)
OSDSystem {
  onAdd: options.onTrackChange !== false ? "card" : "none"
  onChange: options.onTrackChange !== false ? "card" : "none"
  onUpdate: options.onPlayPause === true ? "card" : "none"
  onRemove: "none"
  updateFields: []

  // I18n.tr("Now playing")
  exposes: [
    {
      "key": "media",
      "part": "card",
      "icon": "music_note",
      "label": "Now playing",
      "design": "MediaCard",
      "preview": true
    }
  ]

  // state: { value (the track's title, "" with no active player), player
  // (its name), title, artist, playing, art (the cover's URL) }; lit while
  // a track plays
  function tile(key, state) {
    return {
      "on": !!state?.value && state?.playing === true
    };
  }

  // What MediaCard draws, for the record: the title, the artist (else the
  // player's name), the cover, playing or paused
  function card(change, state) {
    const s = state.media ?? {};
    return {
      "icon": s.playing === true ? "play_arrow" : "pause",
      "image": s.art ?? "",
      "title": s.title ?? "",
      "role": s.artist || s.player || ""
    };
  }
}
