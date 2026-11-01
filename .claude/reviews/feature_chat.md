# feature:chat
reviewed: f8e13e3 2026-11-01  (full)

The chat matches its doc closely; the Go request building and streaming are sound and tested. Open: replacing the conversation drops a launcher question asked while a reply streams and leaves discarded attachments on disk, images dropped together overwrite each other, an image-only message to Anthropic may be rejected, Stop is lost during the key lookup, hidden lists and picker are built, and 9 lines of deletions.

## Open findings
- Major: [Replacing the chat's conversation leaves its reply and attachments behind](../../docs/dev/issues.md#replacing-the-chats-conversation-leaves-its-reply-and-attachments-behind)
- Major: [Images dropped together on the chat overwrite each other](../../docs/dev/issues.md#images-dropped-together-on-the-chat-overwrite-each-other)
- Major: [An image sent without text to Anthropic carries a whitespace-only text block](../../docs/dev/issues.md#an-image-sent-without-text-to-anthropic-carries-a-whitespace-only-text-block)
- Major: [Stop is ignored while chat.send still looks up the key](../../docs/dev/issues.md#stop-is-ignored-while-chatsend-still-looks-up-the-key)
- Major: [The chat builds its conversation lists and model picker while hidden](../../docs/dev/issues.md#the-chat-builds-its-conversation-lists-and-model-picker-while-hidden)
- Minor: [An attachment's thumbnail pokes past its rounded corners](../../docs/dev/issues.md#an-attachments-thumbnail-pokes-past-its-rounded-corners)
- Cleanup: [package chat's Log option is never used](../../docs/dev/issues.md#package-chats-log-option-is-never-used)
- Cleanup: [ChatManager.copy only forwards to ClipboardManager.copyText](../../docs/dev/issues.md#chatmanagercopy-only-forwards-to-clipboardmanagercopytext)
- Minor: chat.md says an unmapped failure becomes `bad_reply`, `_reply` maps it to `""` (`services/apps/ChatManager.qml:461`); the `config` errorKind (line 428) is in neither the doc nor the header. Fix: the doc.
- Minor: `streamStarted`, `thinkingEnded`, `chatDir`, `persistent`, `maxImageBytes` are used only inside ChatManager: `_` names.
- Minor: ConversationList's Today / Yesterday groups (`ConversationList.qml:25`) go stale past midnight until the list changes.
- Minor: an earlier message's Delete shows while a reply streams but `removeMessage` returns on `busy` silently.
- Known, not re-filed: [A fast chat reply can drop the shell's connection](../../docs/dev/issues.md#a-fast-chat-reply-can-drop-the-shells-connection) (unchanged); [Unbounded lists still built in full](../../docs/dev/issues.md#unbounded-lists-still-built-in-full) (ChatMessageList, ConversationList); [A cancelled rename's typed text comes back in the notes and chat rename fields](../../docs/dev/issues.md#a-cancelled-renames-typed-text-comes-back-in-the-notes-and-chat-rename-fields).

## Contract
Holds: the state shape, storage under `chats/` through FileManager.write with the index and pruning to `keepConversations`, `chat.send`'s wire shape without the key, keys from keyEnv then the Secret Service then secrets.json, `chat.delta` to the asking connection, the answer shape and error kinds (but the doc's `bad_reply`), `chat.stop` (but before the key lookup), thinking blocks only to their own model, `chat.models` (null for another API, OpenAI filtered), nothing through QML/argv/files, 50 ms flushing with the placeholder replaced at the end, ChatMarkdown's split (tested), Chat as a Panel, IPC `chat`, the launcher's `@` and `/chat`, pages through `OverlayConfig.pageWithModule` (via `ShellManager.openModule`), creation from `shell.qml`'s `_services`.

## Coverage
Read deeply: ChatManager, send.go, chat.go, keys.go, daemon/chat.go, Chat.qml, ChatMessage, ChatMessageList, ChatComposer, ConversationList, ChatConfig, AttachmentChip, ChatMarkdownText, ChatMarkdown, ChatHeader. Outlined: ModelPicker, ChatThinking, ChatCodeBlock, BackendManager's call/drop handling, secrets.Lookup, CodeLine. Skipped: tests beyond TestBuild/TestStop (by grep).

## History
- 2026-11-01 full: 12 findings (5 Major, 2 Cleanup, 5 Minor; the thumbnail's corners downgraded to Minor in review); recorded
