# Chat

> **Files:** `services/apps/ChatManager.qml`, `backend/internal/chat/`, `backend/internal/daemon/chat.go`, `components/methods/ChatMarkdown.qml`, `components/content/Chat/Chat.qml`
> **Config:** `Chat.*` (reader `ChatConfig`)
> **Related:** [Secrets](../core/secrets.md), [Screenshots and recording](screenshots-recording.md), [Launcher](launcher.md), [Services pattern](../core/services-pattern.md)

The LLM chat: conversations, streaming replies from Anthropic, OpenAI-style and Gemini servers, attachments, and the panel that shows them. Read this before touching the chat service, its requests (in axiom) or the Chat panel.

### State (ChatManager)
- `conversation`: `{ id, title, preset, provider, model, messages }`.
- `conversations`: the index, newest first.
- Actions: `send` / `stop` / `regenerate`, plus presets and models.
- Attachments come from the clipboard, a region from `ScreenshotManager.pick`, or dropped files. axiom reads them by path on each send.
- **Storage:** chats are saved to `$XDG_STATE_HOME/axiom/chats/`:
  - `<id>.json` for each chat
  - `index.json` for the list
  - a `<id>/` folder for that chat's attachments.
- Only the newest `Chat.keepConversations` chats are kept.

### Requests (axiom's package chat)
- Each reply is one `chat.send` call (`ChatManager._reply`): the provider (no key), the model, the messages (only what goes to the provider: role, text, state, who wrote a reply and its `blocks`, attachments' `path` and `mime`) and the preset's options, under an `id`.
- axiom (`backend/internal/chat`) reads the key itself (`keys.go`: `keyEnv` in the shell's environment, then `secret-tool`, then secrets.json; see [Secrets](../core/secrets.md)), reads each attachment by path (one it can't read goes without its image), builds the request and streams the reply:
  - each piece is a `chat.delta` push (`{ id, kind: "text" | "thinking", text }`) to the connection that asked;
  - the call answers when the reply ends: `{ model, blocks, notice: "refusal" | "length" | "", stopped }`;
  - a failure is an error by kind, which `ChatManager` maps to the message's `errorKind`: `unauthorized` (401, 403) → `auth`, `not_found` (no key) → `nokey`, `unavailable` (no answer, or the reply cut off midway) → `network`, else `bad_reply` (another status, an error event in the stream).
- `chat.stop { id }` ends a reply early; `chat.send` then answers `stopped`, with what streamed kept.
- Three provider kinds: `anthropic`, `openai` (any OpenAI-style server), `gemini`.
- Anthropic thinking blocks (with their signatures) are sent back only to the model that wrote them.
- Settings → Chat's Test and Fetch models: `ChatManager.fetchModels(provider, cb)` → `chat.models` (`{ models }`, `null` when the address isn't that kind of API; OpenAI's own list filtered to chat models).
- Nothing about a request passes through QML, argv or a file: the key never leaves axiom, and the body (images included, which can be larger than a protocol message) is built there.

### Streaming
- Streamed text lives in `streamingText` / `streamingThinking`, flushed every 50 ms.
- It replaces the placeholder message only when the reply ends, so the message list doesn't rebuild on every token.

### Display
- `components/methods/ChatMarkdown` splits a reply into prose and code blocks.
- `content/Chat/Chat.qml` is a `Panel`, so it can also be used as a popout.

### Entry points
- IPC `chat`: `open`, `newChat`, `ask <text>`, `settings`.
- Launcher: `@` and `/chat`.
- `OverlayConfig.pageWithModule(type)` finds the page to open.
- Created from `shell.qml`'s `_services`, because of its IPC target.
