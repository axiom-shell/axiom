# Chat

> **Files:** `services/apps/ChatManager.qml`, `services/apps/ChatRequest.qml`, `components/methods/ChatProtocol.qml`, `components/methods/ChatMarkdown.qml`, `components/content/Chat/Chat.qml`
> **Config:** `Chat.*` (reader `ChatConfig`)
> **Related:** [Secrets](../core/secrets.md), [Screenshots and recording](screenshots-recording.md), [Launcher](launcher.md), [Services pattern](../core/services-pattern.md)

The LLM chat: conversations, streaming replies from Anthropic, OpenAI-style and Gemini servers, attachments, and the panel that shows them. Read this before touching the chat service, its protocol helpers or the Chat panel.

### State (ChatManager)
- `conversation`: `{ id, title, preset, provider, model, messages }`.
- `conversations`: the index, newest first.
- Actions: `send` / `stop` / `regenerate`, plus presets and models.
- Attachments come from the clipboard, a region from `ScreenshotManager.pick`, or dropped files. They are base64-encoded on each send.
- **Storage:** chats are saved to `$XDG_STATE_HOME/axiom/chats/`:
  - `<id>.json` for each chat
  - `index.json` for the list
  - a `<id>/` folder for that chat's attachments.
- Only the newest `Chat.keepConversations` chats are kept.

### Requests (ChatRequest)
- Each reply is one `services/apps/ChatRequest`, which runs curl:
  - the curl config, API key included, goes in on stdin via `-K -` (never argv);
  - the request body goes in a file under `$XDG_RUNTIME_DIR`;
  - a `SplitParser` feeds the SSE lines to `components/methods/ChatProtocol`.
- `ChatProtocol` builds the requests and parses the streams for three provider kinds:
  - `anthropic`
  - `openai` (any OpenAI-style server)
  - `gemini`
- Anthropic thinking blocks (with their signatures) are sent back only to the model that wrote them.

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
