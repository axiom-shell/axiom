pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Claude plan usage (the numbers Claude Code's /usage shows) for one or more
// Claude Code accounts, each a CLAUDE_CONFIG_DIR: axiom's `claudeUsage`
// topic, which reads api.anthropic.com/api/oauth/usage with the OAuth token
// in the dir's .credentials.json (the token never reaches the shell). An
// expired token marks the account `expired`, keeping its last numbers,
// until Claude Code refreshes it. The endpoint rate limits hard, so axiom
// fetches each account at most once per interval (across restarts) and
// backs off after a failure, honouring Retry-After on a 429.
// Widgets register with acquire(owner, { accounts: [{label, configDir}],
// interval (ms) }) and drop it with release(owner).
QtObject {
  id: root

  // { <expanded configDir>: { label, dir, org, plan, status, error,
  //   fetchedAt, session, weekly, weeklyOpus, weeklySonnet, extra,
  //   breakdown, retryAt, failures, rateLimited } };
  //   status: pending | ok | expired | error | missing.
  // A window is { percent, resetsAt } or null.
  property var states: ({})

  function acquire(owner, request) {
    _registry.acquire(owner, {
      "interval": Math.max(60000, request?.interval ?? 300000),
      "accounts": (request?.accounts ?? []).filter(a => a?.configDir).map(a => ({
            "label": a.label ?? "",
            "dir": Paths.expandHome(a.configDir)
          }))
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  // Refetches every account now, except those still rate limited
  function refresh() {
    BackendManager.refresh("claudeUsage");
  }

  function stateFor(configDir) {
    return root.states[Paths.expandHome(configDir)] ?? null;
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}

  // The merged request as one string, so axiom is asked again only when it
  // really changes. axiom ticks each minute to see which accounts are due
  // (`interval`) and fetches each at most every `every`.
  readonly property string _requestKey: {
    if (!_registry.active)
      return "";
    const requests = _registry.requests;
    const accounts = [];
    requests.forEach(r => r.accounts.forEach(a => {
        if (!accounts.some(x => x.dir === a.dir && x.label === a.label))
          accounts.push(a);
      }));
    return JSON.stringify({
      "interval": 60000,
      "every": Math.min(...requests.map(r => r.interval)),
      "accounts": accounts
    });
  }

  on_RequestKeyChanged: {
    if (root._requestKey !== "")
      BackendManager.acquire("claudeUsage", JSON.parse(root._requestKey));
    else
      BackendManager.release("claudeUsage");
  }

  Component.onCompleted: BackendManager.listen("claudeUsage.state", state => root.states = state)
}
