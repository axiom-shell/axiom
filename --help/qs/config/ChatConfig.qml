pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Chat section. API keys are not config: see SecretsManager.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Chat

  // Chat.providers, each with an `id` (from its name when left empty) and
  // a `defaultModel` (the first model when left empty)
  readonly property var providers: _c.providers.map((provider, index) => Object.assign({}, provider, {
      "id": provider.id || provider.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "provider-" + (index + 1),
      "name": provider.name || provider.id || "Provider " + (index + 1),
      "defaultModel": provider.defaultModel || (provider.models ?? [])[0] || ""
    }))
  // Chat.providers as saved (no filled-in ids or names), for editing
  readonly property var savedProviders: _c.providers
  readonly property var presets: _c.presets.filter(preset => preset.name !== "")
  readonly property string defaultProvider: _c.defaultProvider
  readonly property string defaultPreset: _c.defaultPreset
  readonly property int maxTokens: _c.maxTokens
  // 0: conversations aren't saved
  readonly property int keepConversations: _c.keepConversations
  readonly property bool showThinking: _c.showThinking
  readonly property bool renderMarkdown: _c.renderMarkdown
  // "enter" | "ctrlEnter"
  readonly property string sendKey: _c.sendKey

  // A provider by id: the default, else the first, for an unknown one
  function provider(id) {
    return root.providers.find(p => p.id === id) ?? root.providers.find(p => p.id === root.defaultProvider) ?? root.providers[0] ?? null;
  }

  // A preset by name (the default, else the first, for an unknown one);
  // never null, so a config without presets still chats
  function preset(name) {
    return root.presets.find(p => p.name === name) ?? root.presets.find(p => p.name === root.defaultPreset) ?? root.presets[0] ?? {
      "name": "Default",
      "icon": "chat",
      "systemPrompt": "",
      "provider": "",
      "model": "",
      "effort": "default"
    };
  }
}
