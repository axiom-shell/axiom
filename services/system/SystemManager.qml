pragma Singleton
import QtQuick
import qs.config
import qs.services.core
import qs.services.ui

// CPU / memory / temperature / GPU / disk usage, sampled by axiom (the
// `system` topic) only while something is showing it. Consumers register
// what they need with acquire(owner, {interval, metrics, diskPaths}) and
// drop it with release(owner); axiom reads the union of requested metrics
// at the fastest requested interval (never under 250 ms), and stops
// entirely when nothing is registered.
//
// Everything is a sysfs / procfs read in Go, so sampling never spawns a
// process; the exception is NVIDIA GPUs (`nvidia-smi`, only without an AMD
// card). Disk usage is re-read once a minute. Metric names: "cpu", "mem",
// "cpuTemp", "gpu", "disk", "net" (throughput from /proc/net/dev; the
// connection itself is NetworkingManager's) and "processes" (/proc/<pid>/
// stat, %CPU since the last sample).
// Request `history: true` to also keep the last `historyLength` samples of
// each polled metric (for graphs), one per sample axiom pushes. The
// metrics any configured graph shows (SystemGraphs modules, SystemStats
// popouts) are kept from launch, so a graph opens with a minute already
// drawn.
QtObject {
  id: root

  // -- Public --
  property real cpuUsage: 0
  property real cpuTemp: 0
  property real memUsage: 0
  property real memUsedBytes: 0
  property real memTotalBytes: 0
  property real gpuUsage: 0
  property real gpuTemp: 0
  // Mount path -> { used, total, usage } for every requested disk path
  property var disks: ({})
  // Bytes per second, summed over every interface but loopback
  property real netRx: 0
  property real netTx: 0
  // [{ pid, user, cpu, mem, command }], every process, by CPU (descending)
  property var processes: []

  // Oldest first, `historyLength` samples at most (only kept on request)
  readonly property int historyLength: 60
  property var cpuHistory: []
  property var memHistory: []
  property var gpuHistory: []
  property var cpuTempHistory: []
  property var netRxHistory: []
  property var netTxHistory: []

  // What this machine can report, known from axiom's first sample
  property bool hasCpuTemp: false
  property bool hasGpu: false

  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": request?.interval ?? 2000,
      "metrics": request?.metrics ?? [],
      "diskPaths": request?.diskPaths ?? [],
      "history": request?.history ?? false
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  function wants(metric) {
    return root._metrics.includes(metric);
  }

  // SIGTERM, from axiom; the list is sampled again straight after
  function kill(pid) {
    BackendManager.call("system.kill", {
      "pid": pid
    }, error => {
      if (error)
        console.warn(`[SystemManager] Could not end ${pid}: ${error.message}`);
      BackendManager.refresh("system");
    });
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}

  // Every metric a configured graph shows, from config only: SystemGraphs
  // modules on overlay pages and enabled edge menus, and the popouts of
  // SystemStats bar widgets (the metrics their bar shows)
  readonly property var _graphMetrics: {
    const found = [];
    const fromModules = modules => (modules ?? []).forEach(module => {
        if (module?.type === "SystemGraphs")
          found.push(...(module.properties?.metrics ?? []));
      });
    (OverlayConfig.views ?? []).forEach(view => fromModules(view?.layout?.modules));
    EdgeMenusConfig.enabledMenus.forEach(menu => fromModules(menu.layout.modules));
    BarManager.bars.forEach(bar => Object.values(bar?.widgets ?? {}).forEach(section => (section ?? []).forEach(widget => {
          const p = widget?.properties;
          if (widget?.type !== "SystemStats" || !p?.popout?.enabled)
            return;
          if (p.showCpu)
            found.push("cpu");
          if (p.showMemory)
            found.push("mem");
          if (p.showTemp)
            found.push("cpuTemp");
          if (p.showGpu)
            found.push("gpu");
        })));
    return ["cpu", "mem", "gpu", "cpuTemp", "net"].filter(m => found.includes(m));
  }
  on_GraphMetricsChanged: _keepGraphHistory()

  // Held under the service itself; the interval matches SystemGraphs'
  function _keepGraphHistory() {
    if (_graphMetrics.length === 0)
      release(root);
    else
      acquire(root, {
        "metrics": _graphMetrics,
        "history": true,
        "interval": 1000
      });
  }
  readonly property var _requests: _registry.requests

  // (the QML JS engine has no Array.flatMap)
  readonly property var _metrics: [...new Set([].concat(..._requests.map(r => r.metrics)))]
  readonly property var _diskPaths: [...new Set([].concat(..._requests.map(r => r.diskPaths)))]
  readonly property bool _history: _requests.some(r => r.history)
  readonly property int _interval: _requests.length > 0 ? Math.min(..._requests.map(r => r.interval)) : 0
  // The request as one string, so axiom is asked again only when it
  // really changes (axiom keys disks by the path as asked, ~ and all)
  readonly property string _requestKey: _registry.active ? JSON.stringify({
    "interval": root._interval,
    "metrics": root._metrics,
    "diskPaths": root._diskPaths
  }) : ""

  on_RequestKeyChanged: {
    if (root._requestKey !== "")
      BackendManager.acquire("system", JSON.parse(root._requestKey));
    else
      BackendManager.release("system");
  }

  // Samples the new values into the histories
  function _record() {
    if (!_history)
      return;
    const push = (list, value) => {
      const next = list.concat([value]);
      return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    };
    if (wants("cpu"))
      cpuHistory = push(cpuHistory, cpuUsage);
    if (wants("mem"))
      memHistory = push(memHistory, memUsage);
    if (wants("gpu"))
      gpuHistory = push(gpuHistory, gpuUsage);
    if (wants("cpuTemp"))
      cpuTempHistory = push(cpuTempHistory, cpuTemp);
    if (wants("net")) {
      netRxHistory = push(netRxHistory, netRx);
      netTxHistory = push(netTxHistory, netTx);
    }
  }

  // One sample: a metric left out wasn't asked for, or has nothing to
  // measure against yet (the first CPU or network sample)
  function _apply(state) {
    root.hasCpuTemp = state.hasCpuTemp;
    root.hasGpu = state.hasGpu;
    for (const key of ["cpuUsage", "cpuTemp", "memUsage", "memUsedBytes", "memTotalBytes", "gpuUsage", "gpuTemp", "netRx", "netTx", "disks", "processes"]) {
      if (state[key] !== undefined)
        root[key] = state[key];
    }
    root._record();
  }

  Component.onCompleted: {
    root._keepGraphHistory();
    BackendManager.listen("system.state", state => root._apply(state));
  }
}
