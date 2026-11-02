import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "NotificationLevel"

  function test_levelOf_data() {
    return [
      {
        tag: "a rule wins",
        rule: "silent",
        urgency: 1,
        low: "alert",
        want: "silent"
      },
      {
        tag: "a rule's alert beats low urgency",
        rule: "alert",
        urgency: 0,
        low: "silent",
        want: "alert"
      },
      {
        tag: "low urgency, no rule",
        rule: "",
        urgency: 0,
        low: "silent",
        want: "silent"
      },
      {
        tag: "low urgency kept loud",
        rule: "",
        urgency: 0,
        low: "alert",
        want: "alert"
      },
      {
        tag: "normal",
        rule: "",
        urgency: 1,
        low: "silent",
        want: "alert"
      },
      {
        tag: "a silent rule lets a critical one alert",
        rule: "silent",
        urgency: 2,
        low: "silent",
        want: "alert"
      },
      {
        tag: "a block rule still blocks a critical one",
        rule: "off",
        urgency: 2,
        low: "silent",
        want: "off"
      },
      {
        tag: "critical",
        rule: "",
        urgency: 2,
        low: "silent",
        want: "alert"
      },
    ];
  }

  function test_levelOf(row) {
    compare(NotificationLevel.levelOf(row.rule, row.urgency, row.low), row.want);
  }

  function test_toasts() {
    verify(NotificationLevel.toasts("alert", false, true, 1));
    verify(NotificationLevel.toasts("toast", false, true, 1));
    verify(!NotificationLevel.toasts("silent", false, true, 2), "silent never toasts, even critical");
    verify(!NotificationLevel.toasts("off", false, true, 1));
    verify(!NotificationLevel.toasts("alert", true, true, 1), "do not disturb");
    verify(NotificationLevel.toasts("alert", true, true, 2), "critical through do not disturb");
    verify(!NotificationLevel.toasts("alert", true, false, 2), "unless that's off");
  }

  function test_files() {
    verify(NotificationLevel.files("alert", false));
    verify(NotificationLevel.files("silent", false));
    verify(!NotificationLevel.files("toast", false));
    verify(!NotificationLevel.files("off", false));
    verify(!NotificationLevel.files("alert", true), "transient ones are never kept");
  }

  function entry(uid, time, silent) {
    return {
      uid: uid,
      time: time,
      silent: silent
    };
  }

  function uids(list) {
    return list.map(e => e.uid);
  }

  function test_kept_limits_each_part_apart() {
    const list = [entry("a1", 10, false), entry("q1", 50, true), entry("a2", 40, false), entry("q2", 30, true), entry("q3", 20, true)];
    const limits = {
      maxEntries: 5,
      maxAge: 0,
      quietMaxEntries: 2,
      quietMaxAge: 0
    };
    compare(uids(NotificationLevel.kept(list, 100, limits)), ["q1", "a2", "q2", "a1"], "the oldest silent one goes; alerts keep their room");
  }

  function test_kept_ages() {
    const list = [entry("a1", 10, false), entry("a2", 90, false), entry("q1", 10, true), entry("q2", 80, true)];
    const limits = {
      maxEntries: 10,
      maxAge: 50,
      quietMaxEntries: 10,
      quietMaxAge: 0
    };
    compare(uids(NotificationLevel.kept(list, 100, limits)), ["a2", "q2", "q1"], "quiet age 0 keeps old silent ones");
  }

  function test_kept_empty() {
    compare(NotificationLevel.kept(undefined, 0, {
      maxEntries: 1,
      maxAge: 0,
      quietMaxEntries: 1,
      quietMaxAge: 0
    }), []);
  }

  function test_groupKey_data() {
    return [
      {
        tag: "an app",
        entry: {
          appName: "Firefox",
          desktopEntry: "firefox"
        },
        want: "Firefox"
      },
      {
        tag: "no app name",
        entry: {
          appName: "",
          desktopEntry: "org.telegram.desktop"
        },
        want: "org.telegram.desktop"
      },
      {
        tag: "a shell source",
        entry: {
          appName: "axiom",
          desktopEntry: "axiom-drives"
        },
        want: "axiom-drives"
      },
      {
        tag: "the shell without a source",
        entry: {
          appName: "axiom",
          desktopEntry: ""
        },
        want: "axiom"
      },
      {
        tag: "nothing",
        entry: {},
        want: ""
      },
    ];
  }

  function test_groupKey(row) {
    compare(NotificationLevel.groupKey(row.entry), row.want);
  }
}
