pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config

/**
 * Secrets, which never go in config.json: chat API keys (scope `provider`)
 * and calendar account passwords (scope `calendar`). axiom keeps them
 * (backend/internal/secrets: the keyring through `secret-tool`, under
 * `service axiom <scope> <id>`, else $XDG_STATE_HOME/axiom/secrets.json,
 * mode 600) and reads them itself (packages chat and calendar; a
 * provider's `keyEnv` environment variable wins over a stored key). This
 * only stores and clears what the user types (`secrets.set`,
 * `secrets.clear`) and asks where each one is (`secrets.status`): no
 * secret is ever read back into QML.
 */
QtObject {
  id: root

  readonly property string secretsPath: Paths.userStatePath.replace(/\/$/, "") + "/secrets.json"

  // Whether a Secret Service answered (null until axiom says)
  property var keyringAvailable: null

  // { slot: "keyring" | "file" | "none", and for a provider "env" |
  // "unneeded" } (a slot is a provider's id, or "<scope>:<id>"), for the
  // settings cards. refresh() and refreshSecrets() fill it.
  property var statuses: ({})

  // Where a provider's key comes from: "env" | "keyring" | "file" |
  // "none" | "unneeded", or "" while it's being looked up
  function status(provider) {
    if (!provider)
      return "none";
    if (provider.auth === "none")
      return "unneeded";
    return root.statuses[provider.id] ?? "";
  }

  // Asks axiom where every provider's key is again (after it changed
  // elsewhere)
  function refresh(providers) {
    root._askStatus((providers ?? []).map(p => ({
          "id": p.id,
          "auth": p.auth,
          "keyEnv": p.keyEnv
        })), []);
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

  // Asks where these calendar accounts' passwords are, for a card showing
  // their status (only scope "calendar" has ids to ask by)
  function refreshSecrets(scope, ids) {
    if (scope === "calendar")
      root._askStatus([], ids ?? []);
  }

  // Stores a secret (`label` names it in the keyring); an empty one clears it
  function setSecret(scope, id, label, value) {
    const slot = root._slot(scope, id);
    BackendManager.call("secrets.set", {
      "scope": scope,
      "id": id,
      "label": label,
      "value": String(value ?? "")
    }, (error, result) => {
      if (error)
        return console.warn("[SecretsManager] Couldn't store the secret for", slot + ":", error.message);
      root._setStatus(slot, result.source);
    });
  }

  function clearSecret(scope, id) {
    const slot = root._slot(scope, id);
    BackendManager.call("secrets.clear", {
      "scope": scope,
      "id": id
    }, error => error ? console.warn("[SecretsManager] Couldn't clear the secret for", slot + ":", error.message) : root._setStatus(slot, "none"));
  }

  // -- Private --

  // Where a secret is in the statuses: a provider's bare id (as before
  // scopes), else "<scope>:<id>"
  function _slot(scope, id) {
    return scope === "provider" ? id : scope + ":" + id;
  }

  function _askStatus(providers, calendars) {
    BackendManager.call("secrets.status", {
      "providers": providers,
      "calendars": calendars
    }, (error, result) => {
      if (error) {
        console.warn("[SecretsManager] Couldn't ask where the secrets are:", error.message);
        return;
      }
      if (root.keyringAvailable === null && !result.keyring)
        console.log("[SecretsManager] No keyring: secrets go to", root.secretsPath);
      root.keyringAvailable = result.keyring;
      root.statuses = Object.assign({}, root.statuses, result.statuses);
    });
  }

  function _setStatus(id, value) {
    // A provider's keyEnv wins over what's stored (axiom reads it first)
    if (root.statuses[id] === "env")
      return;
    const next = Object.assign({}, root.statuses);
    next[id] = value;
    root.statuses = next;
  }

  Component.onCompleted: root.refresh(ChatConfig.providers)
}
