# Secrets

> **Files:** `services/core/SecretsManager.qml`, `backend/internal/secrets/secrets.go`, `backend/internal/daemon/secrets.go`, `backend/internal/chat/keys.go`, `components/views/Settings/ChatProvidersCard.qml`, `components/views/Settings/CalendarAccountsCard.qml`
> **Config:** none (secrets never go in config.json); a provider's `keyEnv`
> **Related:** [Chat](../features/chat.md), [Calendar](../features/calendar.md), [Protocol](../backend/protocol.md)

Where API keys and passwords live. (Rule: AGENTS.md › Services, "Secrets".) axiom keeps and reads them (package `secrets`); no secret is ever read back into QML. The only secret QML holds is what the user types into a key or password field, sent once to `secrets.set`.

### Scopes
- `provider`: chat API keys.
- `calendar`: calendar account passwords.

### Lookup order
1. A provider's `keyEnv` environment variable (chat only, `chat/keys.go`, from the shell's environment).
2. The keyring (`secret-tool`, `service axiom <scope> <id>`).
3. `$XDG_STATE_HOME/axiom/secrets.json` (mode 600). A provider's key sits under its bare id (as before scopes existed); any other under `<scope>:<id>`.

Package chat reads a key for `chat.send` and `chat.models`, and package calendar a CalDAV account's password by its id for every `calendar.*` call, both through `secrets.Store.Lookup`.

### Methods (`daemon/secrets.go`)
- `secrets.status` (`{ providers: [{ id, auth, keyEnv }], calendars: [id] }` → `{ keyring, statuses: { <id> | calendar:<id>: env | keyring | file | none | unneeded } }`): where each one is, and whether a Secret Service answers (a `lookup` of something never stored fails quietly when one does).
- `secrets.set` (`{ scope, id, label, value }` → `{ source }`): stores it in the keyring (the value on secret-tool's stdin, never argv), dropping the file's copy; else in secrets.json. An empty value clears it.
- `secrets.clear` (`{ scope, id }`): from both.
- secrets.json is rewritten atomically (`fsx.WriteFile`) at mode 600 (an existing file's mode is fixed first), and never over a file that doesn't parse (`unavailable`).

### API
- `keyringAvailable`, `secretsPath`: for the card's "stored in" line.
- `secretStatus(scope, id)`: `keyring` | `file` | `none` ("" until asked).
- `setSecret(scope, id, label, value)` / `clearSecret(scope, id)`: `secrets.set` / `secrets.clear`, then the status.
- `refreshSecrets("calendar", ids)`: for a card showing them.
- Provider wrappers: `status` (plus `unneeded`), `setKey`, `clearKey`, `refresh` (asks `secrets.status`; also at start).

### Where they're entered
- Keys: `views/Settings/ChatProvidersCard` (the Chat section's `x-card`, with Test and Fetch models).
- Passwords: `CalendarAccountsCard`.
- Never through the settings draft.
- A key never goes in config.json. The binary's store hands secrets a migration step pulls out of the file to its `OnSecrets` before writing it back; no step pulls any out now.
