pragma Singleton
import QtQuick

// Which media player is the active one, for MediaManager: the one the user
// pinned, else the one that most recently started playing, else the last
// active one, else one that can play, else the first. No file access,
// processes or services.
QtObject {
  id: root

  // The id of the active player of `players` ([{ id, playing, canPlay,
  // startedAt }], startedAt in ms, 0 for unknown), or "" when there are
  // none. `pinnedId` and `lastActiveId` count only while present.
  function pick(players, pinnedId, lastActiveId) {
    const pinned = players.find(p => pinnedId && p.id === pinnedId);
    const playing = players.filter(p => p.playing).reduce((best, p) => best && best.startedAt >= p.startedAt ? best : p, null);
    const last = players.find(p => lastActiveId && p.id === lastActiveId);
    const chosen = pinned ?? playing ?? last ?? players.find(p => p.canPlay) ?? players[0];
    return chosen ? chosen.id : "";
  }
}
