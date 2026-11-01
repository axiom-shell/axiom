import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Schedules"

  function test_minutes() {
    compare(Schedules.minutes("07:30"), 450);
    compare(Schedules.minutes("7:05"), 425);
    compare(Schedules.minutes("00:00"), 0);
    compare(Schedules.minutes("23:59"), 1439);
    compare(Schedules.minutes("24:00"), -1);
    compare(Schedules.minutes("12:60"), -1);
    compare(Schedules.minutes("noon"), -1);
    compare(Schedules.minutes(""), -1);
    compare(Schedules.minutes(undefined), -1);
  }

  function test_minutesOf() {
    compare(Schedules.minutesOf(new Date(2026, 8, 28, 19, 45)), 1185);
  }

  function test_dayWindow() {
    verify(Schedules.inWindow(Schedules.minutes("07:00"), "07:00", "19:00"), "start is in");
    verify(Schedules.inWindow(Schedules.minutes("12:00"), "07:00", "19:00"));
    verify(!Schedules.inWindow(Schedules.minutes("19:00"), "07:00", "19:00"), "end is out");
    verify(!Schedules.inWindow(Schedules.minutes("06:59"), "07:00", "19:00"));
    verify(!Schedules.inWindow(Schedules.minutes("23:00"), "07:00", "19:00"));
  }

  function test_windowPastMidnight() {
    verify(Schedules.inWindow(Schedules.minutes("20:00"), "20:00", "07:00"));
    verify(Schedules.inWindow(Schedules.minutes("23:59"), "20:00", "07:00"));
    verify(Schedules.inWindow(0, "20:00", "07:00"));
    verify(Schedules.inWindow(Schedules.minutes("06:59"), "20:00", "07:00"));
    verify(!Schedules.inWindow(Schedules.minutes("07:00"), "20:00", "07:00"));
    verify(!Schedules.inWindow(Schedules.minutes("12:00"), "20:00", "07:00"));
  }

  function test_emptyOrBadWindow() {
    verify(!Schedules.inWindow(600, "10:00", "10:00"));
    verify(!Schedules.inWindow(600, "bad", "12:00"));
    verify(!Schedules.inWindow(600, "08:00", ""));
  }

  readonly property var walls: ["file:///w/a.jpg", "file:///w/b.jpg", "file:///w/c.jpg"]

  function test_sequential() {
    compare(Schedules.nextWallpaper(walls, walls[0], "sequential", [], 0), walls[1]);
    compare(Schedules.nextWallpaper(walls, walls[2], "sequential", [], 0), walls[0], "wraps");
    compare(Schedules.nextWallpaper(walls, "file:///elsewhere.png", "sequential", [], 0), walls[0], "unlisted starts over");
  }

  function test_randomNeverRepeats() {
    for (const r of [0, 0.3, 0.6, 0.99])
      verify(Schedules.nextWallpaper(walls, walls[1], "random", [], r) !== walls[1]);
  }

  function test_randomAvoidsTaken() {
    compare(Schedules.nextWallpaper(walls, walls[0], "random", [walls[1]], 0.99), walls[2]);
    // Everything else taken: still not the current one
    compare(Schedules.nextWallpaper(walls, walls[0], "random", [walls[1], walls[2]], 0), walls[1]);
  }

  function test_smallLists() {
    compare(Schedules.nextWallpaper([], "", "random", [], 0.5), "");
    compare(Schedules.nextWallpaper([walls[0]], walls[0], "random", [], 0.5), walls[0], "only one: keeps it");
    compare(Schedules.nextWallpaper([walls[0]], walls[0], "sequential", [], 0), walls[0]);
  }

  function test_shuffleShowsEachOnce() {
    let bag = null;
    let current = walls[0];
    const seen = [];
    for (let i = 0; i < walls.length - 1; i++) {
      const next = Schedules.shuffleWallpaper(walls, bag, current, [], 0.5);
      verify(!seen.includes(next.url) && next.url !== walls[0], "no repeat within a round: " + next.url);
      seen.push(next.url);
      bag = next.bag;
      current = next.url;
    }
    compare(bag, [], "the round is over");
    const again = Schedules.shuffleWallpaper(walls, bag, current, [], 0);
    verify(again.url !== current, "a new round never starts with the one showing");
  }

  function test_shuffleDropsGoneFiles() {
    const next = Schedules.shuffleWallpaper([walls[0], walls[1]], ["file:///gone.png", walls[1]], walls[0], [], 0);
    compare(next, {
      "url": walls[1],
      "bag": []
    });
  }

  function test_shuffleAvoidsTaken() {
    compare(Schedules.shuffleWallpaper(walls, null, walls[0], [walls[1]], 0).url, walls[2]);
    compare(Schedules.shuffleWallpaper(walls, [walls[1]], walls[0], [walls[1]], 0).url, walls[1], "the bag's last, taken or not");
  }

  function test_shuffleSmallLists() {
    compare(Schedules.shuffleWallpaper([], null, "", [], 0.5), {
      "url": "",
      "bag": []
    });
    compare(Schedules.shuffleWallpaper([walls[0]], null, walls[0], [], 0.5).url, walls[0], "only one: keeps it");
  }
}
