.pragma library
// Media's timelines: the Now playing card (the cover, the title, the
// artist, playing or paused) on a new track (`onTrackChange`, default on)
// and optionally on play and pause (`onPlayPause`, default off). A new
// track is the title changing, on the same player or another (a player
// appearing with one is a new track too); nothing with no player or no
// title.
//
// State by key (MediaWatch, MediaManager):
//   media  { value (the track: trackTitle while a player is active, else
//          ""), player (MediaManager.identity, "" with no active player),
//          title (trackTitle), artist (trackArtist), playing (isPlaying),
//          art (artSource) }
//
// decided: one key, `media`, part "card", judged by declarations over that
//   state (the track is the scalar's value: a new one an add or a change;
//   playing is its tile's `on`: play/pause an update), each policy set by
//   its option, rather than an event the watcher pulses: the options stay
//   the definition's.
// decided: the card is { title: the track's title, role: its artist, else
//   the player's name, image: the cover, icon: "play_arrow" while playing,
//   else "pause" }, the fields OSDMediaCard draws (it keeps its own design).

var opts = { "onTrackChange": true, "onPlayPause": false };
var both = { "onTrackChange": true, "onPlayPause": true };

function play(title, artist, playing, player, art) {
  const p = player === undefined ? "Spotify" : player;
  return { "value": p ? title : "", "player": p, "title": title, "artist": artist || "", "playing": playing !== false, "art": art || "" };
}

var rows = [
  {
    "name": "the first reading shows nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } }
    ]
  },
  {
    "name": "a new track: its card",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Song B", "Artist", true, "Spotify", "file:///tmp/cover.jpg") },
        "expect": { "key": "media", "show": "card",
          "card": { "title": "Song B", "role": "Artist", "image": "file:///tmp/cover.jpg", "icon": "play_arrow" },
          "host": "open" } }
    ]
  },
  {
    "name": "no artist: the player's name",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "") } },
      { "at": 3000, "state": { "media": play("Episode 12", "", true, "mpv") },
        "expect": { "key": "media", "show": "card", "card": { "title": "Episode 12", "role": "mpv" } } }
    ]
  },
  {
    "name": "a player appearing with a track: a new track",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("", "", false, "") } },
      { "at": 3000, "state": { "media": play("Song A", "Artist") },
        "expect": { "key": "media", "show": "card" } }
    ]
  },
  {
    "name": "another player with another track: a new track",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Video", "Channel", true, "Firefox") },
        "expect": { "key": "media", "show": "card", "card": { "title": "Video" } } }
    ]
  },
  {
    "name": "the title going empty, or the player going: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("", "Artist") } },
      { "at": 6000, "state": { "media": play("", "", false, "") } }
    ]
  },
  {
    "name": "paused, onPlayPause off: nothing",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Song A", "Artist", false) } }
    ]
  },
  {
    "name": "paused and played, onPlayPause on: its card each time",
    "options": both,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Song A", "Artist", false) },
        "expect": { "key": "media", "show": "card", "card": { "icon": "pause" }, "host": "open" } },
      { "at": 6000, "state": { "media": play("Song A", "Artist", true) },
        "expect": { "key": "media", "show": "card", "card": { "icon": "play_arrow" }, "host": "replace" } }
    ]
  },
  {
    "name": "the only player quitting while it plays, onPlayPause on: nothing (no empty card)",
    "options": both,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("", "", false, "") } }
    ]
  },
  {
    "name": "a new track, onTrackChange off: nothing",
    "options": { "onTrackChange": false, "onPlayPause": true },
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Song B", "Artist") } }
    ]
  },
  {
    "name": "a new track starting to play (both at once): one card",
    "options": both,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist", false) } },
      { "at": 3000, "state": { "media": play("Song B", "Artist", true) },
        "expect": { "key": "media", "show": "card" } }
    ]
  },
  {
    "name": "the cover or the artist filling in: nothing",
    "options": both,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "") } },
      { "at": 3000, "state": { "media": play("Song A", "Artist", true, "Spotify", "file:///tmp/cover.jpg") } }
    ]
  },
  {
    "name": "the next track just after: its card replaces",
    "options": opts,
    "steps": [
      { "at": 0, "state": { "media": play("Song A", "Artist") } },
      { "at": 3000, "state": { "media": play("Song B", "Artist") },
        "expect": { "key": "media", "show": "card", "host": "open" } },
      { "at": 3500, "state": { "media": play("Song C", "Artist") },
        "expect": { "key": "media", "show": "card", "card": { "title": "Song C" }, "host": "replace" } }
    ]
  }
];
