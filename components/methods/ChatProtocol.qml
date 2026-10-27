pragma Singleton
import QtQuick

/**
 * The chat providers' wire formats, as pure functions: ChatManager builds a
 * request with request(), ChatRequest sends it with curl and feeds every
 * streamed event to parse(). A provider is a Chat.providers entry, whose
 * `kind` picks the format:
 *   anthropic  the Messages API
 *   openai     Chat Completions (OpenAI, Ollama, LM Studio, OpenRouter, …)
 *   gemini     generateContent
 *
 * A conversation message is { role: "user" | "assistant", text, blocks,
 * attachments: [{ path, mime }], provider, model, state }; only finished
 * user and assistant messages are sent.
 */
QtObject {
  id: root

  // The Messages API accepts these without extended thinking settings
  function _anthropicThinks(model) {
    return !/^claude-(3|haiku)/.test(model);
  }

  function _trimBase(url) {
    return String(url ?? "").replace(/\/+$/, "");
  }

  // Messages worth sending, with consecutive turns of one role merged
  // (a failed reply leaves two user turns in a row)
  function _turns(messages) {
    const turns = [];
    for (const message of messages) {
      if (message.role !== "user" && message.role !== "assistant")
        continue;
      if (message.role === "assistant" && message.state !== "done" && message.state !== "stopped")
        continue;
      if (message.role === "assistant" && !(message.text ?? "").trim())
        continue;
      const last = turns[turns.length - 1];
      if (last && last.role === message.role)
        last.parts.push(message);
      else
        turns.push({
          role: message.role,
          parts: [message]
        });
    }
    return turns;
  }

  function _userText(parts) {
    return parts.map(part => part.text ?? "").filter(text => text !== "").join("\n\n");
  }

  function _images(parts, images) {
    return [].concat(...parts.map(part => (part.attachments ?? []).filter(a => images[a.path]).map(a => ({
            mime: a.mime,
            data: images[a.path]
          }))));
  }

  /**
   * @param provider  a Chat.providers entry
   * @param model     model id
   * @param apiKey    "" when the provider needs none
   * @param messages  the conversation's messages
   * @param options   { system, maxTokens, effort ("default" | low … max),
   *                    showThinking, images: { path: base64 } }
   * @return { url, headers: ["Name: value"], body }
   */
  function request(provider, model, apiKey, messages, options) {
    switch (provider.kind) {
    case "anthropic":
      return _anthropicRequest(provider, model, apiKey, messages, options);
    case "gemini":
      return _geminiRequest(provider, model, apiKey, messages, options);
    }
    return _openaiRequest(provider, model, apiKey, messages, options);
  }

  function _anthropicRequest(provider, model, apiKey, messages, options) {
    const images = options.images ?? {};
    const out = _turns(messages).map(turn => {
      if (turn.role === "user") {
        const content = _images(turn.parts, images).map(image => ({
              type: "image",
              source: {
                type: "base64",
                media_type: image.mime,
                data: image.data
              }
            }));
        content.push({
          type: "text",
          text: _userText(turn.parts) || " "
        });
        return {
          role: "user",
          content: content
        };
      }
      // Thinking blocks go back unchanged, signature and all, but only to
      // the model that wrote them; any other model gets the text
      const content = [].concat(...turn.parts.map(part => {
        const own = part.state === "done" && part.provider === provider.id && part.model === model && (part.blocks ?? []).length > 0;
        if (own)
          return part.blocks.filter(block => ["text", "thinking", "redacted_thinking"].includes(block.type));
        return [
          {
            type: "text",
            text: part.text
          }
        ];
      }));
      return {
        role: "assistant",
        content: content
      };
    });
    const body = {
      model: model,
      max_tokens: options.maxTokens,
      stream: true,
      messages: out
    };
    if (options.system)
      body.system = options.system;
    if (_anthropicThinks(model))
      body.thinking = {
        type: "adaptive",
        display: options.showThinking ? "summarized" : "omitted"
      };
    if (options.effort && options.effort !== "default")
      body.output_config = {
        effort: options.effort
      };
    const headers = ["Content-Type: application/json", "anthropic-version: 2023-06-01", "x-api-key: " + apiKey];
    if (provider.fallbacks) {
      body.fallbacks = "default";
      headers.push("anthropic-beta: server-side-fallback-2026-07-01");
    }
    return {
      url: _trimBase(provider.baseUrl) + "/messages",
      headers: headers,
      body: JSON.stringify(body)
    };
  }

  function _openaiRequest(provider, model, apiKey, messages, options) {
    const images = options.images ?? {};
    const out = [];
    if (options.system)
      out.push({
        role: "system",
        content: options.system
      });
    _turns(messages).forEach(turn => {
      if (turn.role === "assistant") {
        out.push({
          role: "assistant",
          content: turn.parts.map(part => part.text).join("\n\n")
        });
        return;
      }
      const attached = _images(turn.parts, images);
      const text = _userText(turn.parts);
      if (attached.length === 0) {
        out.push({
          role: "user",
          content: text
        });
        return;
      }
      out.push({
        role: "user",
        content: attached.map(image => ({
              type: "image_url",
              image_url: {
                url: `data:${image.mime};base64,${image.data}`
              }
            })).concat(text ? [
          {
            type: "text",
            text: text
          }
        ] : [])
      });
    });
    const body = {
      model: model,
      stream: true,
      messages: out
    };
    // OpenAI's reasoning models reject max_tokens; the servers that copy
    // its API mostly only know max_tokens
    if (/(^|\/\/)api\.openai\.com/.test(provider.baseUrl))
      body.max_completion_tokens = options.maxTokens;
    else
      body.max_tokens = options.maxTokens;
    // Chat Completions tops out at "high"
    if (options.effort && options.effort !== "default")
      body.reasoning_effort = ["xhigh", "max"].includes(options.effort) ? "high" : options.effort;
    const headers = ["Content-Type: application/json"];
    if (provider.auth !== "none")
      headers.push("Authorization: Bearer " + apiKey);
    return {
      url: _trimBase(provider.baseUrl) + "/chat/completions",
      headers: headers,
      body: JSON.stringify(body)
    };
  }

  function _geminiRequest(provider, model, apiKey, messages, options) {
    const images = options.images ?? {};
    const contents = _turns(messages).map(turn => {
      if (turn.role === "assistant")
        return {
          role: "model",
          parts: [
            {
              text: turn.parts.map(part => part.text).join("\n\n")
            }
          ]
        };
      const parts = _images(turn.parts, images).map(image => ({
            inline_data: {
              mime_type: image.mime,
              data: image.data
            }
          }));
      const text = _userText(turn.parts);
      if (text || parts.length === 0)
        parts.push({
          text: text || " "
        });
      return {
        role: "user",
        parts: parts
      };
    });
    const body = {
      contents: contents,
      generationConfig: {
        maxOutputTokens: options.maxTokens,
        thinkingConfig: {
          includeThoughts: !!options.showThinking
        }
      }
    };
    if (options.system)
      body.systemInstruction = {
        parts: [
          {
            text: options.system
          }
        ]
      };
    return {
      url: _trimBase(provider.baseUrl) + "/models/" + encodeURIComponent(model) + ":streamGenerateContent?alt=sse",
      headers: ["Content-Type: application/json", "x-goog-api-key: " + apiKey],
      body: JSON.stringify(body)
    };
  }

  // -- Streaming --

  // The state parse() fills in over one reply
  function newState(model) {
    return {
      blocks: [],
      text: "",
      thinking: "",
      model: model,
      stopReason: "",
      usage: {},
      error: "",
      done: false
    };
  }

  /**
   * One SSE `data:` payload (a string). Updates `state` in place and
   * returns what to show: [{ kind: "text" | "thinking", text }].
   */
  function parse(kind, data, state) {
    if (data === "[DONE]") {
      state.done = true;
      return [];
    }
    let event;
    try {
      event = JSON.parse(data);
    } catch (e) {
      return [];
    }
    if (event?.error) {
      state.error = event.error.message ?? JSON.stringify(event.error);
      return [];
    }
    switch (kind) {
    case "anthropic":
      return _parseAnthropic(event, state);
    case "gemini":
      return _parseGemini(event, state);
    }
    return _parseOpenai(event, state);
  }

  function _append(state, deltaKind, text, out) {
    if (!text)
      return;
    state[deltaKind] += text;
    out.push({
      kind: deltaKind,
      text: text
    });
  }

  function _parseAnthropic(event, state) {
    const out = [];
    switch (event.type) {
    case "message_start":
      state.model = event.message?.model || state.model;
      state.usage = Object.assign({}, state.usage, event.message?.usage ?? {});
      break;
    case "content_block_start":
      state.blocks[event.index] = JSON.parse(JSON.stringify(event.content_block ?? {}));
      break;
    case "content_block_delta":
      {
        const block = state.blocks[event.index] ?? (state.blocks[event.index] = {});
        const delta = event.delta ?? {};
        if (delta.type === "text_delta") {
          block.text = (block.text ?? "") + delta.text;
          _append(state, "text", delta.text, out);
        } else if (delta.type === "thinking_delta") {
          block.thinking = (block.thinking ?? "") + delta.thinking;
          _append(state, "thinking", delta.thinking, out);
        } else if (delta.type === "signature_delta") {
          block.signature = (block.signature ?? "") + delta.signature;
        }
        break;
      }
    case "message_delta":
      state.stopReason = event.delta?.stop_reason ?? state.stopReason;
      state.usage = Object.assign({}, state.usage, event.usage ?? {});
      break;
    case "message_stop":
      state.done = true;
      break;
    }
    return out;
  }

  function _parseOpenai(event, state) {
    const out = [];
    const choice = event.choices?.[0];
    if (event.model)
      state.model = event.model;
    if (event.usage)
      state.usage = event.usage;
    if (!choice)
      return out;
    const delta = choice.delta ?? {};
    _append(state, "thinking", delta.reasoning_content ?? delta.reasoning ?? "", out);
    _append(state, "text", delta.content ?? "", out);
    if (choice.finish_reason)
      state.stopReason = choice.finish_reason;
    return out;
  }

  function _parseGemini(event, state) {
    const out = [];
    const candidate = event.candidates?.[0];
    if (event.usageMetadata)
      state.usage = event.usageMetadata;
    if (event.modelVersion)
      state.model = state.model || event.modelVersion;
    for (const part of candidate?.content?.parts ?? [])
      _append(state, part.thought ? "thinking" : "text", part.text ?? "", out);
    if (candidate?.finishReason)
      state.stopReason = candidate.finishReason;
    return out;
  }

  // The message in an error response body (JSON or not)
  function errorMessage(text) {
    const trimmed = String(text ?? "").trim();
    try {
      const parsed = JSON.parse(trimmed);
      const error = Array.isArray(parsed) ? parsed[0]?.error : parsed.error;
      return error?.message ?? (typeof error === "string" ? error : parsed.message) ?? trimmed;
    } catch (e) {
      return trimmed;
    }
  }

  // Why a reply ended early, for a notice under it ("" when it didn't)
  function stopNotice(stopReason) {
    switch (stopReason) {
    case "refusal":
    case "SAFETY":
    case "content_filter":
      return "refusal";
    case "max_tokens":
    case "length":
    case "MAX_TOKENS":
      return "length";
    }
    return "";
  }
}
