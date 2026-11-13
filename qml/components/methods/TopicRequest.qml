pragma Singleton
import QtQuick

// What a polled topic is asked for, built from every consumer's request in
// one go, so a half-evaluated binding (an interval not set yet, read as 0)
// never reaches axiom. No file access, processes or services.
QtObject {
  id: root

  // The graphed metrics axiom keeps a history of
  readonly property var graphed: ["cpu", "mem", "gpu", "cpuTemp", "net"]

  // `value` when it's a positive finite number, else `fallback`
  function interval(value, fallback) {
    return typeof value === "number" && isFinite(value) && value > 0 ? value : fallback;
  }

  // The `system` topic's request for the consumers' requests ([{ interval,
  // metrics, diskPaths, history }]): the shortest interval, the union of
  // the metrics and disk paths, and the graphed metrics some consumer wants
  // the history of; null with none. Keys are always in this order, so the
  // JSON string of two equal requests is equal.
  function systemRequest(requests) {
    if (!requests || requests.length === 0)
      return null;
    const union = lists => [...new Set([].concat(...lists.map(l => l ?? [])))];
    return {
      "interval": Math.min(...requests.map(r => root.interval(r.interval, 2000))),
      "metrics": union(requests.map(r => r.metrics)),
      "diskPaths": union(requests.map(r => r.diskPaths)),
      "history": union(requests.filter(r => r.history).map(r => r.metrics)).filter(m => root.graphed.includes(m))
    };
  }
}
