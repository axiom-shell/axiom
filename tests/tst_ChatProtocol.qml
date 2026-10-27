import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ChatProtocol"

  function provider(kind, extra) {
    return Object.assign({
      "id": kind,
      "kind": kind,
      "baseUrl": "https://example.test/v1/",
      "auth": "key"
    }, extra ?? {});
  }

  readonly property var messages: [
    {
      "role": "user",
      "text": "first",
      "attachments": [
        {
          "path": "/tmp/a.png",
          "mime": "image/png"
        }
      ]
    },
    {
      "role": "user",
      "text": "again"
    },
    {
      "role": "assistant",
      "text": "reply",
      "state": "done",
      "provider": "anthropic",
      "model": "claude-x",
      "blocks": [
        {
          "type": "thinking",
          "thinking": "hm",
          "signature": "sig"
        },
        {
          "type": "text",
          "text": "reply"
        }
      ]
    },
    {
      "role": "assistant",
      "text": "",
      "state": "streaming"
    },
    {
      "role": "system",
      "text": "notice"
    },
    {
      "role": "user",
      "text": "next"
    }
  ]

  readonly property var options: ({
      "system": "be brief",
      "maxTokens": 100,
      "effort": "max",
      "showThinking": true,
      "images": {
        "/tmp/a.png": "QUJD"
      }
    })

  function body(request) {
    return JSON.parse(request.body);
  }

  function test_anthropic_request() {
    const request = ChatProtocol.request(provider("anthropic", {
      "fallbacks": true
    }), "claude-x", "KEY", messages, options);
    compare(request.url, "https://example.test/v1/messages");
    verify(request.headers.includes("x-api-key: KEY"));
    verify(request.headers.some(h => h.startsWith("anthropic-beta:")));
    const b = body(request);
    compare(b.system, "be brief");
    compare(b.max_tokens, 100);
    compare(b.output_config.effort, "max");
    compare(b.thinking.display, "summarized");
    compare(b.fallbacks, "default");
    // Two user turns merge; the unfinished reply and the notice are dropped
    compare(b.messages.map(m => m.role), ["user", "assistant", "user"]);
    compare(b.messages[0].content[0].type, "image");
    compare(b.messages[0].content[0].source.data, "QUJD");
    compare(b.messages[0].content[1].text, "first\n\nagain");
    // The model that wrote the thinking block gets it back
    compare(b.messages[1].content.map(c => c.type), ["thinking", "text"]);
    compare(b.messages[1].content[0].signature, "sig");
  }

  function test_anthropic_other_model_gets_text_only() {
    const b = body(ChatProtocol.request(provider("anthropic"), "claude-y", "KEY", messages, options));
    compare(JSON.stringify(b.messages[1].content), JSON.stringify([
      {
        "type": "text",
        "text": "reply"
      }
    ]));
  }

  function test_anthropic_old_models_skip_thinking() {
    const b = body(ChatProtocol.request(provider("anthropic"), "claude-3-opus", "KEY", messages, {
      "maxTokens": 10
    }));
    compare(b.thinking, undefined);
    compare(b.output_config, undefined);
  }

  function test_openai_request() {
    const request = ChatProtocol.request(provider("openai"), "gpt", "KEY", messages, options);
    compare(request.url, "https://example.test/v1/chat/completions");
    verify(request.headers.includes("Authorization: Bearer KEY"));
    const b = body(request);
    compare(b.messages[0].role, "system");
    compare(b.messages[1].content[0].image_url.url, "data:image/png;base64,QUJD");
    compare(b.messages[2].content, "reply");
    compare(b.max_tokens, 100);
    compare(b.reasoning_effort, "high");
  }

  function test_openai_official_uses_max_completion_tokens() {
    const b = body(ChatProtocol.request(provider("openai", {
      "baseUrl": "https://api.openai.com/v1"
    }), "gpt", "KEY", messages, options));
    compare(b.max_completion_tokens, 100);
    compare(b.max_tokens, undefined);
  }

  function test_openai_without_auth_sends_no_key() {
    const request = ChatProtocol.request(provider("openai", {
      "auth": "none"
    }), "llama", "", messages, options);
    verify(!request.headers.some(h => h.startsWith("Authorization")));
  }

  function test_gemini_request() {
    const request = ChatProtocol.request(provider("gemini"), "gemini pro", "KEY", messages, options);
    compare(request.url, "https://example.test/v1/models/gemini%20pro:streamGenerateContent?alt=sse");
    const b = body(request);
    compare(b.contents.map(c => c.role), ["user", "model", "user"]);
    compare(b.contents[0].parts[0].inline_data.data, "QUJD");
    compare(b.systemInstruction.parts[0].text, "be brief");
    compare(b.generationConfig.thinkingConfig.includeThoughts, true);
  }

  function stream(kind, events) {
    const state = ChatProtocol.newState("start-model");
    const deltas = [];
    for (const event of events)
      deltas.push(...ChatProtocol.parse(kind, typeof event === "string" ? event : JSON.stringify(event), state));
    return {
      state: state,
      deltas: deltas
    };
  }

  function test_parse_anthropic_stream() {
    const result = stream("anthropic", [
      {
        "type": "message_start",
        "message": {
          "model": "claude-x",
          "usage": {
            "input_tokens": 5
          }
        }
      },
      {
        "type": "content_block_start",
        "index": 0,
        "content_block": {
          "type": "thinking",
          "thinking": ""
        }
      },
      {
        "type": "content_block_delta",
        "index": 0,
        "delta": {
          "type": "thinking_delta",
          "thinking": "hmm"
        }
      },
      {
        "type": "content_block_delta",
        "index": 0,
        "delta": {
          "type": "signature_delta",
          "signature": "abc"
        }
      },
      {
        "type": "content_block_start",
        "index": 1,
        "content_block": {
          "type": "text",
          "text": ""
        }
      },
      {
        "type": "content_block_delta",
        "index": 1,
        "delta": {
          "type": "text_delta",
          "text": "Hel"
        }
      },
      {
        "type": "content_block_delta",
        "index": 1,
        "delta": {
          "type": "text_delta",
          "text": "lo"
        }
      },
      {
        "type": "message_delta",
        "delta": {
          "stop_reason": "end_turn"
        },
        "usage": {
          "output_tokens": 7
        }
      },
      {
        "type": "message_stop"
      }
    ]);
    const s = result.state;
    compare(s.model, "claude-x");
    compare(s.text, "Hello");
    compare(s.thinking, "hmm");
    compare(s.blocks[0].signature, "abc");
    compare(s.blocks[1].text, "Hello");
    compare(s.stopReason, "end_turn");
    compare(s.usage.input_tokens, 5);
    compare(s.usage.output_tokens, 7);
    compare(s.done, true);
    compare(result.deltas.map(d => d.kind), ["thinking", "text", "text"]);
  }

  function test_parse_openai_stream() {
    const result = stream("openai", [
      {
        "model": "gpt-x",
        "choices": [
          {
            "delta": {
              "reasoning_content": "think"
            }
          }
        ]
      },
      {
        "choices": [
          {
            "delta": {
              "content": "Hi"
            },
            "finish_reason": "length"
          }
        ]
      },
      {
        "choices": [],
        "usage": {
          "total_tokens": 3
        }
      },
      "[DONE]"]);
    compare(result.state.text, "Hi");
    compare(result.state.thinking, "think");
    compare(result.state.model, "gpt-x");
    compare(result.state.usage.total_tokens, 3);
    compare(result.state.done, true);
    compare(ChatProtocol.stopNotice(result.state.stopReason), "length");
  }

  function test_parse_gemini_stream() {
    const result = stream("gemini", [
      {
        "candidates": [
          {
            "content": {
              "parts": [
                {
                  "text": "plan",
                  "thought": true
                },
                {
                  "text": "Answer"
                }
              ]
            }
          }
        ]
      },
      {
        "candidates": [
          {
            "finishReason": "SAFETY"
          }
        ],
        "usageMetadata": {
          "totalTokenCount": 9
        }
      }
    ]);
    compare(result.state.text, "Answer");
    compare(result.state.thinking, "plan");
    compare(result.state.model, "start-model");
    compare(ChatProtocol.stopNotice(result.state.stopReason), "refusal");
  }

  function test_parse_errors_and_junk() {
    const result = stream("anthropic", ["not json",
      {
        "type": "error",
        "error": {
          "message": "overloaded"
        }
      }
    ]);
    compare(result.state.error, "overloaded");
    compare(result.deltas, []);
  }

  function test_errorMessage() {
    compare(ChatProtocol.errorMessage('{"error": {"message": "bad key"}}'), "bad key");
    compare(ChatProtocol.errorMessage('[{"error": {"message": "gemini"}}]'), "gemini");
    compare(ChatProtocol.errorMessage('{"error": "plain"}'), "plain");
    compare(ChatProtocol.errorMessage("  502 Bad Gateway \n"), "502 Bad Gateway");
  }
}
