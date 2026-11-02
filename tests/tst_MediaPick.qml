import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "MediaPick"

  function player(id, playing, startedAt, canPlay) {
    return {
      "id": id,
      "playing": playing,
      "canPlay": canPlay ?? true,
      "startedAt": startedAt ?? 0
    };
  }

  function test_none() {
    compare(MediaPick.pick([], "a", "a"), "");
  }

  function test_pinnedFirst() {
    compare(MediaPick.pick([player("a", true, 5), player("b", false)], "b", "a"), "b");
    compare(MediaPick.pick([player("a", true, 5)], "gone", ""), "a", "a pin that's gone counts for nothing");
  }

  function test_mostRecentlyStartedPlaying() {
    compare(MediaPick.pick([player("spotify", false), player("browser", true, 10)], "", "spotify"), "browser", "a playing one over the paused active one");
    compare(MediaPick.pick([player("a", true, 10), player("b", true, 20), player("c", true, 15)], "", "a"), "b");
    compare(MediaPick.pick([player("a", true), player("b", true)], "", ""), "a", "unknown start times: the first");
  }

  function test_lastActive() {
    compare(MediaPick.pick([player("a", false), player("b", false)], "", "b"), "b", "nothing playing: the active one stays");
    compare(MediaPick.pick([player("a", false)], "", "gone"), "a");
  }

  function test_canPlay() {
    compare(MediaPick.pick([player("a", false, 0, false), player("b", false, 0, true)], "", ""), "b");
    compare(MediaPick.pick([player("a", false, 0, false), player("b", false, 0, false)], "", ""), "a", "none can play: the first");
  }
}
