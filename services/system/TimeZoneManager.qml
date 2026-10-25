pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.services.core

// Other time zones' UTC offsets, for clocks set to one (a Clock module's
// or a bar Time widget's `timezone`): the JS engine can't convert times
// between zones (TimeZones). Each zone asked for is read once for all its
// clocks (axiom's tz.offsets, from the system's zoneinfo), again past
// every half hour (when daylight saving changes), and not at all with
// none asked for. Without axiom's daemon (the greeter) the same answers
// come from `axiom tz` (Paths.axiomBin).
//   TimeZoneManager.acquire(owner, "Asia/Tokyo")   // "" releases
//   TimeZoneManager.acquire(owner, ["Asia/Tokyo", "Europe/Paris"])
//   TimeZoneManager.offsetOf("Asia/Tokyo")          // 540, null until read
// Also lists the system's zones (`zones`, tz.zones), for the time zone
// fields.
QtObject {
  id: root

  // zone -> minutes east of UTC
  readonly property var offsets: root._offsets
  property var _offsets: ({})
  // The system's zone names, sorted ([] until read)
  readonly property var zones: root._zones
  property var _zones: []

  // One zone, or a list (World clocks); none releases
  function acquire(owner, zone) {
    const zones = (Array.isArray(zone) ? zone : [zone]).filter(z => !!z).filter((z, i, all) => all.indexOf(z) === i).sort();
    if (zones.length === 0) {
      root.release(owner);
      return;
    }
    root._registry.acquire(owner, {
      "zones": zones
    });
  }

  function release(owner) {
    root._registry.release(owner);
  }

  // A zone's offset, or null (its clock shows the system's time): not read
  // yet, or not one of the system's zones (for which `date` would quietly
  // give UTC)
  function offsetOf(zone) {
    if (!zone || (root._zones.length > 0 && !root._zones.includes(zone)))
      return null;
    return root._offsets[zone] ?? null;
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
  // The zones asked for, as a key: identical requests don't re-read
  readonly property string _wanted: [].concat(...root._registry.requests.map(request => request.zones)).filter((zone, i, all) => all.indexOf(zone) === i).sort().join("\n")
  on_WantedChanged: root._read()
  // Asked again while reading: read once more after
  property bool _again: false
  property bool _reading: false

  function _read() {
    if (root._wanted === "") {
      root._timer.stop();
      return;
    }
    if (root._reading) {
      root._again = true;
      return;
    }
    root._reading = true;
    root._ask("offsets", root._wanted.split("\n"), (error, result) => {
      root._reading = false;
      if (error) {
        if (error.kind !== "unavailable")
          console.warn("[TimeZoneManager] reading offsets failed:", error.message);
      } else {
        const offsets = Object.assign({}, root._offsets, result.offsets);
        if (JSON.stringify(offsets) !== JSON.stringify(root._offsets))
          root._offsets = offsets;
      }
      if (root._again) {
        root._again = false;
        root._read();
        return;
      }
      root._timer.interval = TimeZones.msToNextCheck(new Date());
      root._timer.restart();
    });
  }

  property Timer _timer: Timer {
    repeat: false
    onTriggered: root._read()
  }

  // Asks axiom for tz.zones / tz.offsets (what: "zones" | "offsets"):
  // the daemon, else `axiom tz <what> --json`, which answers the same.
  // done(error, result)
  function _ask(what, zones, done) {
    if (BackendManager.active && what === "zones") {
      BackendManager.call("tz.zones", {}, done);
      return;
    }
    if (BackendManager.active) {
      BackendManager.call("tz.offsets", {
        "zones": zones
      }, done);
      return;
    }
    CommandManager.run([Paths.axiomBin, "tz", what, "--json", "--"].concat(zones), (exitCode, out, err) => {
      let result = null;
      try {
        result = exitCode === 0 ? JSON.parse(out) : null;
      } catch (e) {}
      done(result ? null : {
        "kind": "unavailable",
        "message": err.trim()
      }, result);
    });
  }

  // tzdata's own list ($TZDIR where it's set), until it's had: again
  // after a hello, if the connection dropped before it was answered
  function _readZones() {
    if (root._zones.length > 0 || root._readingZones)
      return;
    root._readingZones = true;
    root._ask("zones", [], (error, result) => {
      root._readingZones = false;
      if (!error)
        root._zones = result.zones;
    });
  }
  property bool _readingZones: false

  property Connections _hello: Connections {
    target: BackendManager
    function onGreeted() {
      root._readZones();
      // A read cut off by the connection dropping, not left to the next
      // half hour (a zone the system lacks never gets one: read again)
      if (root._wanted.split("\n").some(zone => zone !== "" && !(zone in root._offsets)))
        root._read();
    }
  }

  Component.onCompleted: root._readZones()
}
