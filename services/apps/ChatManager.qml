pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs.config
import qs.components.methods
import qs.services.core
import qs.services.system
import qs.services.ui

/*
 * The chat: conversations, sending and streaming replies (ChatRequest,
 * ChatProtocol), attachments, and their history on disk. Every Chat module
 * shows the one current conversation.
 *
 * A conversation is { id, title, created, updated, preset, provider, model,
 * messages }; a message is { role: "user" | "assistant", text, time, and
 * for a reply: thinking, blocks (the provider's raw content, for thinking
 * signatures), provider, model, state: "streaming" | "done" | "stopped" |
 * "error", error, errorKind: "auth" | "nokey" | "network" | "", notice:
 * "refusal" | "length" | "", thinkingMs; for a user message: attachments
 * [{ path, mime, name }] }.
 *
 * Saved as $XDG_STATE_HOME/axiom/chats/<id>.json, with index.json listing
 * them and <id>/ holding attachments, up to Chat.keepConversations.
 *
 *   axiom ipc chat open
 *   axiom ipc chat newChat
 *   axiom ipc chat ask "question"
 *   axiom ipc chat settings
 */
Singleton {
  id: root

  // Summaries, newest first: { id, title, updated, preset, provider, model }
  property var conversations: []
  // Set once the config is read (a binding here would start a new
  // conversation on every config change)
  property var conversation: ({
      messages: []
    })
  readonly property var messages: conversation.messages

  // The reply streaming in: its text and thinking so far (the last
  // message, while its state is "streaming", reads these)
  readonly property bool busy: _request !== null
  property string streamingText: ""
  property string streamingThinking: ""
  // When the reply started, and its thinking ended (0 while it thinks)
  property real streamStarted: 0
  property real thinkingEnded: 0

  // Images waiting to go with the next message
  property var attachments: []
  // Attaching (a clipboard read or screenshot) in progress
  property bool attaching: false
  // A short-lived problem to show under the composer ("" when none)
  property string notice: ""

  readonly property var preset: ChatConfig.preset(conversation.preset)
  readonly property var provider: ChatConfig.provider(conversation.provider)
  readonly property string model: conversation.model || provider?.defaultModel || ""

  readonly property string chatDir: Paths.userStatePath + "chats/"
  readonly property bool persistent: ChatConfig.keepConversations > 0

  // -- Conversations --

  function newConversation(presetName) {
    if (root.busy)
      root.stop();
    root.conversation = _blank(presetName ?? ChatConfig.defaultPreset);
    root.attachments = [];
  }

  function open(id) {
    if (id === root.conversation.id)
      return;
    const loaded = _readConversation(id);
    if (!loaded?.messages) {
      root.notice = I18n.tr("That conversation couldn't be opened.");
      return;
    }
    if (root.busy)
      root.stop();
    // A reply cut off by a reload never finished
    loaded.messages.forEach(m => {
      if (m.state === "streaming")
        m.state = "stopped";
    });
    root.conversation = loaded;
    root.attachments = [];
  }

  function rename(id, title) {
    const trimmed = String(title ?? "").trim();
    if (trimmed === "")
      return;
    if (id === root.conversation.id) {
      _update({
        title: trimmed
      });
      _save();
      return;
    }
    const loaded = _readConversation(id);
    if (!loaded)
      return;
    loaded.title = trimmed;
    _writeConversation(loaded);
  }

  function remove(id) {
    // The id names files to delete: never an empty or made-up one
    if (!_validId(id))
      return;
    root.conversations = root.conversations.filter(c => c.id !== id);
    _saveIndex();
    Quickshell.execDetached(["rm", "-rf", "--", root.chatDir + id + ".json", root.chatDir + id]);
    if (id === root.conversation.id)
      root.newConversation(root.conversation.preset);
  }

  function setPreset(name) {
    const preset = ChatConfig.preset(name);
    _update({
      preset: preset.name,
      provider: preset.provider || root.conversation.provider,
      model: preset.model || (preset.provider ? "" : root.conversation.model)
    });
  }

  function setModel(providerId, model) {
    _update({
      provider: providerId,
      model: model
    });
  }

  // -- Sending --

  function send(text) {
    const trimmed = String(text ?? "").trim();
    if ((trimmed === "" && root.attachments.length === 0) || root.busy)
      return false;
    const message = {
      role: "user",
      text: trimmed,
      time: Date.now(),
      attachments: root.attachments
    };
    const title = root.conversation.messages.length === 0 ? _titleFrom(trimmed) : root.conversation.title;
    root.attachments = [];
    root.notice = "";
    _update({
      title: title,
      messages: root.conversation.messages.concat([message])
    });
    _save();
    _reply();
    return true;
  }

  // A new conversation with the default preset, on the overlay's chat page
  function ask(text) {
    root.newConversation(ChatConfig.defaultPreset);
    root.openPage();
    root.send(text);
  }

  function stop() {
    if (root._request)
      root._request.stop();
  }

  // The last reply again (after an error, or for a different answer)
  function regenerate() {
    if (root.busy)
      return;
    const messages = root.conversation.messages.slice();
    while (messages.length > 0 && messages[messages.length - 1].role === "assistant")
      messages.pop();
    if (messages.length === 0)
      return;
    _update({
      messages: messages
    });
    _reply();
  }

  function removeMessage(index) {
    if (root.busy)
      return;
    const messages = root.conversation.messages.slice();
    messages.splice(index, 1);
    _update({
      messages: messages
    });
    _save();
  }

  function copy(text) {
    ClipboardManager.copyText(text);
  }

  // Settings → Chat (keys, providers, presets)
  function openSettings() {
    SettingsManager.openSetting("Chat");
  }

  // Opens the overlay on the page with the (biggest) Chat module, else an
  // edge menu with one (moving the cursor into it)
  function openPage() {
    if (ShellManager.openModule(["Chat"]))
      return true;
    NotificationManager.sendNotification("axiom", I18n.tr("No chat module"), I18n.tr("Add a Chat module to an overlay page or an edge menu."));
    return false;
  }

  // -- Attachments --

  // Largest image a provider takes (Anthropic's limit; the others allow more)
  readonly property int maxImageBytes: 5 * 1024 * 1024

  function attachClipboard() {
    if (root.attaching)
      return;
    root.attaching = true;
    root.notice = "";
    _run(["sh", "-c", "wl-paste --list-types 2>/dev/null | grep -m1 -E '^image/(png|jpeg|webp|gif)$'"], (ok, out) => {
      const mime = out.trim();
      if (!ok || mime === "") {
        root.attaching = false;
        root.notice = I18n.tr("There's no image on the clipboard.");
        return;
      }
      const path = _attachmentPath(mime.split("/")[1]);
      _run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && wl-paste --type \"$2\" > \"$1\"", "sh", path, mime], ok => _attached(ok, path, mime, I18n.tr("Pasted image")));
    });
  }

  // Closes the overlay, lets you pick a region (ScreenshotManager's
  // picker), then reopens on the chat
  function attachScreenshot() {
    if (root.attaching)
      return;
    const path = _attachmentPath("png");
    const started = ScreenshotManager.pick(path, ok => {
      root.openPage();
      if (!ok) {
        root.attaching = false;
        return;
      }
      _attached(true, path, "image/png", I18n.tr("Screenshot"));
    });
    if (!started)
      return;
    root.attaching = true;
    root.notice = "";
  }

  // A file dropped on the chat (a file:// URL)
  function attachFile(url) {
    const path = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    const ext = (path.match(/\.([a-z0-9]+)$/i)?.[1] ?? "").toLowerCase();
    const mime = {
      "png": "image/png",
      "jpg": "image/jpeg",
      "jpeg": "image/jpeg",
      "webp": "image/webp",
      "gif": "image/gif"
    }[ext];
    if (!mime) {
      root.notice = I18n.tr("Only images can be attached.");
      return;
    }
    const copy = _attachmentPath(ext === "jpeg" ? "jpg" : ext);
    root.attaching = true;
    _run(["sh", "-c", "mkdir -p \"$(dirname \"$2\")\" && cp -- \"$1\" \"$2\"", "sh", path, copy], ok => _attached(ok, copy, mime, path.split("/").pop()));
  }

  function detach(index) {
    const next = root.attachments.slice();
    const removed = next.splice(index, 1)[0];
    root.attachments = next;
    if (removed)
      Quickshell.execDetached(["rm", "-f", "--", removed.path]);
  }

  // -- Private --

  property ChatRequest _request: null
  // base64 of every attachment sent this session, by path
  property var _encoded: ({})
  property string _pendingText: ""
  property string _pendingThinking: ""

  function _blank(presetName) {
    const preset = ChatConfig.preset(presetName);
    const now = Date.now();
    return {
      id: now.toString(36) + Math.floor(Math.random() * 1e6).toString(36),
      title: "",
      created: now,
      updated: now,
      preset: preset.name,
      provider: preset.provider || ChatConfig.defaultProvider,
      model: preset.model,
      messages: []
    };
  }

  // Ids are made by _blank (base 36), so they're safe in a path
  function _validId(id) {
    return /^[a-z0-9]+$/.test(String(id ?? ""));
  }

  // A saved conversation, or null when it's missing or unreadable
  function _readConversation(id) {
    if (!_validId(id))
      return null;
    const text = FileManager.read("file://" + root.chatDir + id + ".json");
    try {
      return text ? JSON.parse(text) : null;
    } catch (e) {
      console.warn("[ChatManager] Could not parse conversation", id, e);
      return null;
    }
  }

  function _update(changes) {
    root.conversation = Object.assign({}, root.conversation, changes);
  }

  function _titleFrom(text) {
    const line = text.split("\n")[0].trim();
    return line.length > 60 ? line.substring(0, 57).trim() + "…" : line || I18n.tr("Image");
  }

  function _attachmentPath(ext) {
    const dir = root.persistent ? root.chatDir + root.conversation.id : Paths.runtimePath + "chat/" + root.conversation.id;
    return `${dir}/${Date.now().toString(36)}.${ext}`;
  }

  function _attached(ok, path, mime, name) {
    if (!ok) {
      root.attaching = false;
      root.notice = I18n.tr("Couldn't attach the image.");
      return;
    }
    _run(["stat", "-c", "%s", path], (statOk, out) => {
      root.attaching = false;
      const size = parseInt(out) || 0;
      if (!statOk || size === 0) {
        root.notice = I18n.tr("Couldn't attach the image.");
        return;
      }
      if (size > root.maxImageBytes) {
        Quickshell.execDetached(["rm", "-f", "--", path]);
        root.notice = I18n.tr("That image is over {0} MB.", Math.round(root.maxImageBytes / 1024 / 1024));
        return;
      }
      root.attachments = root.attachments.concat([
        {
          path: path,
          mime: mime,
          name: name
        }
      ]);
    });
  }

  // Encodes every attachment in the conversation not encoded yet, then
  // calls back
  function _encodeAll(messages, callback) {
    const paths = [].concat(...messages.map(m => (m.attachments ?? []).map(a => a.path))).filter(path => root._encoded[path] === undefined);
    if (paths.length === 0)
      return callback();
    const path = paths[0];
    _run(["base64", "-w0", "--", path], (ok, out) => {
      // A missing file (deleted by hand) is sent without its image
      root._encoded[path] = ok ? out.trim() : "";
      _encodeAll(messages, callback);
    });
  }

  function _reply() {
    const provider = root.provider;
    const model = root.model;
    const placeholder = {
      role: "assistant",
      text: "",
      thinking: "",
      provider: provider?.id ?? "",
      model: model,
      state: "streaming",
      time: Date.now()
    };
    const history = root.conversation.messages;
    _update({
      messages: history.concat([placeholder])
    });
    root.streamingText = "";
    root.streamingThinking = "";
    root._pendingText = "";
    root._pendingThinking = "";
    root.streamStarted = Date.now();
    root.thinkingEnded = 0;

    if (!provider)
      return _fail("nokey", I18n.tr("No chat provider is set up. Add one in Settings → Chat."));
    if (!model)
      return _fail("config", I18n.tr("{0} has no model to use. Add one in Settings → Chat.", provider.name));

    const request = _requestComponent.createObject(root, {
      kind: provider.kind
    });
    root._request = request;
    SecretsManager.withKey(provider, key => {
      if (root._request !== request)
        return;
      if (provider.auth !== "none" && !key)
        return _fail("nokey", I18n.tr("No API key for {0}.", provider.name));
      _encodeAll(history, () => {
        if (root._request !== request)
          return;
        const body = ChatProtocol.request(provider, model, key, history, {
          system: root.preset.systemPrompt,
          maxTokens: ChatConfig.maxTokens,
          effort: root.preset.effort,
          showThinking: ChatConfig.showThinking,
          images: root._encoded
        });
        request.start(body, model);
      });
    });
  }

  function _onDelta(kind, text) {
    if (kind === "thinking") {
      root._pendingThinking += text;
    } else {
      if (root.thinkingEnded === 0 && (root.streamingThinking !== "" || root._pendingThinking !== ""))
        root.thinkingEnded = Date.now();
      root._pendingText += text;
    }
    if (!_flush.running)
      _flush.start();
  }

  function _flushNow() {
    if (root._pendingThinking !== "") {
      root.streamingThinking += root._pendingThinking;
      root._pendingThinking = "";
    }
    if (root._pendingText !== "") {
      root.streamingText += root._pendingText;
      root._pendingText = "";
    }
  }

  // Replaces the streaming placeholder with the finished reply
  function _finish(changes) {
    _flushNow();
    _flush.stop();
    const messages = root.conversation.messages.slice();
    const last = messages[messages.length - 1];
    if (last?.role !== "assistant" || last.state !== "streaming")
      return;
    const thinkingMs = root.streamingThinking === "" ? 0 : (root.thinkingEnded || Date.now()) - root.streamStarted;
    messages[messages.length - 1] = Object.assign({}, last, {
      text: root.streamingText,
      thinking: root.streamingThinking,
      thinkingMs: thinkingMs
    }, changes);
    if (root._request) {
      root._request.destroy();
      root._request = null;
    }
    _update({
      messages: messages
    });
    root.streamingText = "";
    root.streamingThinking = "";
    _save();
  }

  function _fail(kind, message) {
    _finish({
      state: "error",
      errorKind: kind,
      error: message
    });
  }

  function _onFinished(request, state) {
    if (request !== root._request)
      return;
    _finish({
      state: request.stopped ? "stopped" : "done",
      model: state.model || root.model,
      blocks: request.stopped ? [] : state.blocks.filter(b => b),
      notice: ChatProtocol.stopNotice(state.stopReason)
    });
  }

  function _onFailed(request, status, message) {
    if (request !== root._request)
      return;
    const kind = status === 401 || status === 403 ? "auth" : status === 0 ? "network" : "";
    _fail(kind, status > 0 ? `${status}: ${message}` : message);
  }

  // -- Disk --

  function _save() {
    if (!root.persistent || root.conversation.messages.length === 0)
      return;
    _writeConversation(Object.assign({}, root.conversation, {
      updated: Date.now()
    }));
  }

  function _writeConversation(conversation) {
    _writeFile(root.chatDir + conversation.id + ".json", JSON.stringify(conversation));
    const summary = {
      id: conversation.id,
      title: conversation.title,
      updated: conversation.updated,
      preset: conversation.preset,
      provider: conversation.provider,
      model: conversation.model
    };
    let list = [summary].concat(root.conversations.filter(c => c.id !== conversation.id));
    list.sort((a, b) => b.updated - a.updated);
    // Past the limit: the oldest go, attachments and all
    const dropped = list.slice(ChatConfig.keepConversations);
    list = list.slice(0, ChatConfig.keepConversations);
    dropped.forEach(c => Quickshell.execDetached(["rm", "-rf", "--", root.chatDir + c.id + ".json", root.chatDir + c.id]));
    root.conversations = list;
    _saveIndex();
  }

  function _saveIndex() {
    _writeFile(root.chatDir + "index.json", JSON.stringify(root.conversations, null, 1));
  }

  function _writeFile(path, text) {
    const view = _fileComponent.createObject(root, {
      path: path
    });
    view.setText(text);
    view.destroy();
  }

  function _loadIndex() {
    const text = FileManager.read("file://" + root.chatDir + "index.json");
    if (!text)
      return [];
    try {
      const list = JSON.parse(text);
      return Array.isArray(list) ? list : [];
    } catch (e) {
      console.warn("[ChatManager] Could not parse the conversation index:", e);
      return [];
    }
  }

  // Runs a command and calls back with (ok, stdout)
  function _run(command, callback) {
    CommandManager.run(command, (code, out) => callback(code === 0, out));
  }

  Timer {
    id: _flush
    // Streamed text is laid out at most this often: a reply re-renders
    // its Markdown on each flush, not on each token
    interval: 50
    onTriggered: root._flushNow()
  }

  Timer {
    id: _noticeClear
    interval: 5000
    onTriggered: root.notice = ""
  }

  onNoticeChanged: {
    if (root.notice !== "")
      _noticeClear.restart();
  }

  property Component _requestComponent: Component {
    ChatRequest {
      id: request
      onDelta: (kind, text) => root._onDelta(kind, text)
      onFinished: state => root._onFinished(request, state)
      onFailed: (status, message) => root._onFailed(request, status, message)
    }
  }

  property Component _fileComponent: Component {
    FileView {
      blockWrites: true
      atomicWrites: true
      printErrors: false
      onSaveFailed: error => console.warn("[ChatManager] Could not save", path + ":", FileViewError.toString(error))
    }
  }

  IpcTarget {
    target: "chat"

    // The overlay, on the chat page
    function open(): void {
      root.openPage();
    }

    function newChat(): void {
      root.newConversation(ChatConfig.defaultPreset);
      root.openPage();
    }

    function ask(text: string): void {
      root.ask(text);
    }

    // Settings → Chat (keys, providers, presets)
    function settings(): void {
      root.openSettings();
    }
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.chatDir]);
    root.conversations = root._loadIndex();
    root.conversation = _blank(ChatConfig.defaultPreset);
    // Pick up where the last conversation left off
    if (root.conversations.length > 0) {
      root.open(root.conversations[0].id);
      root.notice = "";
    }
    console.log("[ChatManager] Started:", root.conversations.length, "conversations; provider", root.conversation.provider, "default", ChatConfig.defaultProvider);
  }
}
