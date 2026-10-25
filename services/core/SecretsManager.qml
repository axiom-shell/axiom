pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config

/**
 * Secrets, which never go in config.json: chat API keys (scope `provider`)
 * and calendar account passwords (scope `calendar`). A secret is the first
 * of:
 *   1. a provider's `keyEnv` environment variable (e.g. ANTHROPIC_API_KEY)
 *   2. the keyring (Secret Service, through `secret-tool`), under
 *      `service axiom <scope> <id>`
 *   3. $XDG_STATE_HOME/axiom/secrets.json ({ "<id>": "…" } for providers,
 *      "<scope>:<id>" for the other scopes; mode 600)
 * setSecret() stores one in the keyring when one answers, else in the file.
 * Secrets go to secret-tool and the file through stdin, never argv.
 */
QtObject {
  id: root

  readonly property string stateDir: Paths.userStatePath.replace(/\/$/, "")
  readonly property string secretsPath: stateDir + "/secrets.json"

  // Whether a Secret Service answered (null until the probe finishes)
  property var keyringAvailable: null

  // { slot: "keyring" | "file" | "none" } (a slot is a provider's id, or
  // "<scope>:<id>"), for the settings cards. refresh() and lookups fill it.
  property var statuses: ({})

  // Where a provider's key would come from; "" while it's being looked up
  function status(provider) {
    if (!provider)
      return "none";
    if (provider.auth === "none")
      return "unneeded";
    if (provider.keyEnv && Quickshell.env(provider.keyEnv))
      return "env";
    return root.secretStatus("provider", provider.id);
  }

  // Calls back with the provider's key, "" when there is none
  function withKey(provider, callback) {
    if (provider.auth === "none")
      return callback("");
    const fromEnv = provider.keyEnv ? Quickshell.env(provider.keyEnv) : "";
    if (fromEnv)
      return callback(fromEnv);
    root.withSecret("provider", provider.id, callback);
  }

  // Looks every provider's key up again (after it changed elsewhere)
  function refresh(providers) {
    root._clearCache("provider");
    root._secrets = root._read();
    for (const provider of providers ?? [])
      if (provider.auth !== "none")
        root._lookup("provider", provider.id, () => {});
  }

  function setKey(provider, key) {
    root.setSecret("provider", provider.id, provider.name || provider.id, key);
  }

  function clearKey(provider) {
    root.clearSecret("provider", provider.id);
  }

  // --- Any scope ---

  // "keyring" | "file" | "none", or "" while it's being looked up
  function secretStatus(scope, id) {
    return root.statuses[root._slot(scope, id)] ?? "";
  }

  // Calls back with the secret, "" when there is none
  function withSecret(scope, id, callback) {
    const slot = root._slot(scope, id);
    if (root._cache[slot] !== undefined)
      return callback(root._cache[slot]);
    root._lookup(scope, id, callback);
  }

  // Looks these ids' secrets up again, for a card showing their status
  function refreshSecrets(scope, ids) {
    root._clearCache(scope);
    root._secrets = root._read();
    for (const id of ids ?? [])
      root._lookup(scope, id, () => {});
  }

  // Stores a secret (`label` names it in the keyring); an empty one clears it
  function setSecret(scope, id, label, value) {
    const trimmed = String(value ?? "").trim();
    if (trimmed === "")
      return root.clearSecret(scope, id);
    const slot = root._slot(scope, id);
    root._cache[slot] = trimmed;
    if (root.keyringAvailable) {
      root._run(["secret-tool", "store", "--label=" + "Axiom: " + label, "service", "axiom", scope, id], trimmed, ok => {
        if (!ok) {
          console.warn("[SecretsManager] The keyring refused the secret for", slot + "; saving it to", root.secretsPath);
          root._storeFile(slot, trimmed);
          return;
        }
        root._setStatus(slot, "keyring");
        // One place per secret: the file's copy would outlive a later clear
        if (root._secrets[slot] !== undefined)
          root._storeFile(slot, undefined);
      });
      return;
    }
    root._storeFile(slot, trimmed);
  }

  function clearSecret(scope, id) {
    const slot = root._slot(scope, id);
    delete root._cache[slot];
    if (root._secrets[slot] !== undefined)
      root._storeFile(slot, undefined);
    if (root.keyringAvailable)
      root._run(["secret-tool", "clear", "service", "axiom", scope, id], null, () => root._lookup(scope, id, () => {}));
    else
      root._setStatus(slot, "none");
  }

  // -- Private --

  property var _secrets: _read()
  // Secrets looked up this session (by slot), so each request doesn't run
  // secret-tool
  property var _cache: ({})

  // Where a secret is in the file, the statuses and the cache: a provider's
  // bare id (as before scopes), else "<scope>:<id>"
  function _slot(scope, id) {
    return scope === "provider" ? id : scope + ":" + id;
  }

  function _clearCache(scope) {
    for (const slot of Object.keys(root._cache))
      if (scope === "provider" ? !slot.includes(":") : slot.startsWith(scope + ":"))
        delete root._cache[slot];
  }

  function _setStatus(id, value) {
    const next = Object.assign({}, root.statuses);
    next[id] = value;
    root.statuses = next;
  }

  // Lookups asked for before the keyring probe answers, run after it: until
  // then a keyring key would read as missing (and be cached as "")
  property var _waiting: []

  function _lookup(scope, id, callback) {
    if (root.keyringAvailable === null) {
      root._waiting.push(() => root._lookup(scope, id, callback));
      return;
    }
    const slot = root._slot(scope, id);
    const fromFile = () => {
      const key = root._secrets[slot] ?? "";
      root._cache[slot] = key;
      root._setStatus(slot, key ? "file" : "none");
      callback(key);
    };
    if (!root.keyringAvailable)
      return fromFile();
    root._run(["secret-tool", "lookup", "service", "axiom", scope, id], null, (ok, out) => {
      const key = ok ? out.trim() : "";
      if (!key)
        return fromFile();
      root._cache[slot] = key;
      root._setStatus(slot, "keyring");
      callback(key);
    });
  }

  function _storeFile(id, key) {
    const merged = Object.assign({}, root._secrets);
    if (key === undefined)
      delete merged[id];
    else
      merged[id] = key;
    root._secrets = merged;
    if (key !== undefined)
      root._setStatus(id, "file");
    else if (root.statuses[id] === "file")
      root._setStatus(id, "none");
    // chmod also fixes an existing file's mode
    root._run(["sh", "-c", "umask 077 && mkdir -p \"$(dirname \"$1\")\" && cat > \"$1\" && chmod 600 \"$1\"", "sh", root.secretsPath], JSON.stringify(merged, null, 2), ok => {
      if (!ok)
        console.warn("[SecretsManager] Failed to write", root.secretsPath);
    });
  }

  function _read() {
    const content = FileManager.read("file://" + root.secretsPath);
    if (!content)
      return {};
    try {
      return JSON.parse(content);
    } catch (e) {
      console.warn("[SecretsManager] Could not parse", root.secretsPath, e);
      return {};
    }
  }

  // Runs a command, writing `input` (if any) to its stdin, then calls
  // back with (ok, stdout, stderr)
  function _run(command, input, callback) {
    CommandManager.run(command, (code, out, err) => callback(code === 0, out, err), input);
  }

  Component.onCompleted: {
    // `lookup` of something never stored fails quietly (exit 1, nothing on
    // stderr) when a Secret Service answers, and complains when none does
    root._run(["sh", "-c", "command -v secret-tool >/dev/null || { echo 'secret-tool is not installed' >&2; exit 127; }; exec secret-tool lookup service axiom-probe probe probe"], null, (ok, out, err) => {
      root.keyringAvailable = err.trim() === "";
      if (!root.keyringAvailable)
        console.log("[SecretsManager] No keyring:", err.trim(), "- keys go to", root.secretsPath);
      root.refresh(ChatConfig.providers);
      const waiting = root._waiting;
      root._waiting = [];
      waiting.forEach(lookup => lookup());
    });
  }
}
