import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "Search"

  function test_score() {
    compare(Search.score("Firefox", "firefox"), 100);
    compare(Search.score("Firefox", "fire"), 80);
    compare(Search.score("Visual Studio Code", "code"), 65, "at a word start");
    compare(Search.score("Thunderbird", "bird"), 50, "inside a word");
    compare(Search.score("Firefox", "ffx"), 22, "letters in order, spread out");
    compare(Search.score("Firefox", "xf"), 0, "letters out of order");
    compare(Search.score("Firefox", "z"), 0, "one letter must match as a substring");
    compare(Search.score("", "a"), 0);
    compare(Search.score("Firefox", ""), 0);
  }

  function test_rankIcons() {
    const entries = [["search", "find magnify"], ["home", "house"], ["volume_up", "audio sound speaker"], ["volume_off", "audio mute"], ["speaker", "audio sound"], ["music_note", "audio song"]];
    compare(Search.rankIcons(entries, "", 2), ["search", "home"], "no query: the most popular");
    compare(Search.rankIcons(entries, "volume", 5), ["volume_up", "volume_off"], "by name prefix, in catalog order");
    compare(Search.rankIcons(entries, "volume up", 5), ["volume_up"], "spaces read as underscores");
    compare(Search.rankIcons(entries, "speaker", 5), ["speaker", "volume_up"], "the name first, then a tag");
    compare(Search.rankIcons(entries, "audio", 2), ["volume_up", "volume_off"], "tags, limited");
    compare(Search.rankIcons(entries, "sound mute", 5), [], "every word must match");
    compare(Search.rankIcons(entries, "off", 5), ["volume_off"], "a word inside the name");
    compare(Search.rankIcons(entries, "zzz", 5), []);
    compare(Search.rankIcons(entries, "magn", 5), ["search"], "a search word's start");
    compare(Search.rankIcons(entries, "aker", 5), ["speaker"], "inside the name, but never inside a search word");
  }

  function test_frecency() {
    const now = Date.UTC(2026, 9, 8);
    const day = 86400000;
    compare(Search.frecency(undefined, now), 0);
    compare(Search.frecency({
      count: 4,
      last: now - day / 2
    }, now), 4);
    compare(Search.frecency({
      count: 10,
      last: now - 3 * day
    }, now), 7);
    compare(Search.frecency({
      count: 10,
      last: now - 10 * day
    }, now), 5);
    compare(Search.frecency({
      count: 10,
      last: now - 90 * day
    }, now), 2.5);
  }

  function test_looksLikeMath() {
    verify(Search.looksLikeMath("2+2"));
    verify(Search.looksLikeMath("(3 × 4) ÷ 2"));
    verify(Search.looksLikeMath("5!"));
    verify(!Search.looksLikeMath("42"), "no operator");
    verify(!Search.looksLikeMath("+-"), "no digit");
    verify(!Search.looksLikeMath("5 km to mi"), "words go through =");
  }
}
