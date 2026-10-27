package chat

import (
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

const (
	// An attachment bigger than this is sent without its image: the
	// shell refuses anything over 5 MB, so only a file changed since is
	maxImage = 8 << 20
	// One SSE line; a provider's events are a few KB
	maxEvent = 4 << 20
)

// Message is a conversation message, as the shell sends it: only
// finished user and assistant messages are sent on.
type Message struct {
	Role  string `json:"role"` // "user" or "assistant"
	Text  string `json:"text"`
	State string `json:"state,omitempty"` // a reply's: "done", "stopped", …
	// Who wrote a reply, and its raw content (thinking blocks with their
	// signatures), sent back unchanged to the same model
	Provider    string           `json:"provider,omitempty"`
	Model       string           `json:"model,omitempty"`
	Blocks      []map[string]any `json:"blocks,omitempty"`
	Attachments []Attachment     `json:"attachments,omitempty"`
}

// Attachment is an image on a user message, read here from its path.
type Attachment struct {
	Path string `json:"path"`
	Mime string `json:"mime"`
}

// SendRequest is one reply to ask for.
type SendRequest struct {
	// Names the reply in its chat.delta pushes and in chat.stop
	ID           string    `json:"id"`
	Provider     Provider  `json:"provider"`
	Model        string    `json:"model"`
	Messages     []Message `json:"messages"`
	System       string    `json:"system,omitempty"`
	MaxTokens    int       `json:"maxTokens"`
	Effort       string    `json:"effort,omitempty"` // "default", "low" … "max"
	ShowThinking bool      `json:"showThinking,omitempty"`
}

// Delta is a piece of the reply streaming in.
type Delta struct {
	ID   string `json:"id"`
	Kind string `json:"kind"` // "text" or "thinking"
	Text string `json:"text"`
}

// SendResult is a reply that ended (its text came as deltas).
type SendResult struct {
	Model string `json:"model"` // the model that answered
	// Anthropic's content blocks, to send back with the next turn (none
	// when stopped)
	Blocks  []map[string]any `json:"blocks"`
	Notice  string           `json:"notice"` // "refusal", "length" or ""
	Stopped bool             `json:"stopped"`
}

// errStopped is why a reply Stop ended
var errStopped = errors.New("stopped")

// Send asks the provider for a reply to the messages, passing each piece
// to emit as it streams in. Stop(id) ends it early, which isn't an
// error: the result says stopped. A failure is unauthorized (401, 403),
// not_found (no key), unavailable (no answer, or the reply cut off
// midway) or bad_reply (any other status, an error in the stream), after
// whatever streamed before it.
func (s *Service) Send(ctx context.Context, r SendRequest, emit func(Delta)) (SendResult, error) {
	key, err := s.keyFor(ctx, r.Provider)
	if err != nil {
		return SendResult{}, err
	}
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	s.mu.Lock()
	s.running[r.ID] = cancel
	s.mu.Unlock()
	defer func() {
		s.mu.Lock()
		delete(s.running, r.ID)
		s.mu.Unlock()
	}()

	target, body := build(r, readImages(r.Messages))
	raw, err := json.Marshal(body)
	if err != nil {
		return SendResult{}, axerr.Wrap(axerr.Internal, err, "encoding the request")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, target, bytes.NewReader(raw))
	if err != nil {
		return SendResult{}, axerr.Wrap(axerr.BadRequest, err, "the address of %s", r.Provider.label())
	}
	req.Header.Set("Content-Type", "application/json")
	r.Provider.header(req.Header, key)
	if r.Provider.Kind == "anthropic" && r.Provider.Fallbacks {
		req.Header.Set("anthropic-beta", "server-side-fallback-2026-07-01")
	}
	st := &stream{kind: r.Provider.Kind, model: r.Model}
	stopped := func() bool { return errors.Is(context.Cause(ctx), errStopped) }
	resp, err := s.o.Client.Do(req)
	if err != nil {
		if stopped() {
			return SendResult{Model: st.model, Blocks: []map[string]any{}, Stopped: true}, nil
		}
		return SendResult{}, transportError(err)
	}
	defer resp.Body.Close()
	if err := statusError(resp); err != nil {
		return SendResult{}, err
	}
	scanner := bufio.NewScanner(resp.Body)
	scanner.Buffer(make([]byte, 64<<10), maxEvent)
	for scanner.Scan() {
		data, ok := strings.CutPrefix(scanner.Text(), "data:")
		if !ok {
			continue
		}
		for _, d := range st.parse(strings.TrimSpace(data)) {
			d.ID = r.ID
			emit(d)
		}
	}
	if stopped() {
		return SendResult{Model: st.model, Blocks: []map[string]any{}, Stopped: true}, nil
	}
	if err := scanner.Err(); err != nil {
		return SendResult{}, axerr.Wrap(axerr.Unavailable, err, "the reply was cut off")
	}
	if st.err != "" {
		return SendResult{}, axerr.New(axerr.BadReply, "%s", st.err)
	}
	blocks := []map[string]any{}
	for _, b := range st.blocks {
		if b != nil {
			blocks = append(blocks, b)
		}
	}
	return SendResult{Model: st.model, Blocks: blocks, Notice: stopNotice(st.stopReason)}, nil
}

// Stop ends the reply named id, if it's still streaming.
func (s *Service) Stop(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if cancel, ok := s.running[id]; ok {
		cancel(errStopped)
	}
}

// readImages is every attachment's base64 by path; one that can't be read
// (deleted by hand) is sent without its image
func readImages(messages []Message) map[string]string {
	images := map[string]string{}
	for _, m := range messages {
		for _, a := range m.Attachments {
			if _, done := images[a.Path]; done {
				continue
			}
			images[a.Path] = ""
			if info, err := os.Stat(a.Path); err != nil || !info.Mode().IsRegular() || info.Size() > maxImage {
				continue
			}
			if data, err := os.ReadFile(a.Path); err == nil {
				images[a.Path] = base64.StdEncoding.EncodeToString(data)
			}
		}
	}
	return images
}

// stopNotice is why a reply ended early, for a notice under it
func stopNotice(reason string) string {
	switch reason {
	case "refusal", "SAFETY", "content_filter":
		return "refusal"
	case "max_tokens", "length", "MAX_TOKENS":
		return "length"
	}
	return ""
}

// -- Requests --

type obj = map[string]any

// turn is consecutive messages of one role, merged (a failed reply leaves
// two user turns in a row)
type turn struct {
	role  string
	parts []Message
}

// turns is the messages worth sending: user messages and finished,
// non-empty replies
func turns(messages []Message) []turn {
	var out []turn
	for _, m := range messages {
		switch {
		case m.Role == "user":
		case m.Role == "assistant" && (m.State == "done" || m.State == "stopped") && strings.TrimSpace(m.Text) != "":
		default:
			continue
		}
		if n := len(out); n > 0 && out[n-1].role == m.Role {
			out[n-1].parts = append(out[n-1].parts, m)
		} else {
			out = append(out, turn{role: m.Role, parts: []Message{m}})
		}
	}
	return out
}

func (t turn) text() string {
	var texts []string
	for _, p := range t.parts {
		if p.Text != "" {
			texts = append(texts, p.Text)
		}
	}
	return strings.Join(texts, "\n\n")
}

type image struct{ mime, data string }

func (t turn) images(images map[string]string) []image {
	var out []image
	for _, p := range t.parts {
		for _, a := range p.Attachments {
			if data := images[a.Path]; data != "" {
				out = append(out, image{a.Mime, data})
			}
		}
	}
	return out
}

func orSpace(s string) string {
	if s == "" {
		return " "
	}
	return s
}

// build is the request for the provider's kind: its URL and JSON body
func build(r SendRequest, images map[string]string) (string, obj) {
	switch r.Provider.Kind {
	case "anthropic":
		return anthropicRequest(r, images)
	case "gemini":
		return geminiRequest(r, images)
	}
	return openaiRequest(r, images)
}

// oldClaude takes no extended thinking settings
var oldClaude = regexp.MustCompile(`^claude-(3|haiku)`)

func anthropicRequest(r SendRequest, images map[string]string) (string, obj) {
	messages := []obj{}
	for _, t := range turns(r.Messages) {
		content := []any{}
		if t.role == "user" {
			for _, img := range t.images(images) {
				content = append(content, obj{"type": "image", "source": obj{"type": "base64", "media_type": img.mime, "data": img.data}})
			}
			content = append(content, obj{"type": "text", "text": orSpace(t.text())})
			messages = append(messages, obj{"role": "user", "content": content})
			continue
		}
		// Thinking blocks go back unchanged, signature and all, but only
		// to the model that wrote them; any other model gets the text
		for _, p := range t.parts {
			if p.State == "done" && p.Provider == r.Provider.ID && p.Model == r.Model && len(p.Blocks) > 0 {
				for _, b := range p.Blocks {
					switch b["type"] {
					case "text", "thinking", "redacted_thinking":
						content = append(content, b)
					}
				}
				continue
			}
			content = append(content, obj{"type": "text", "text": p.Text})
		}
		messages = append(messages, obj{"role": "assistant", "content": content})
	}
	body := obj{"model": r.Model, "max_tokens": r.MaxTokens, "stream": true, "messages": messages}
	if r.System != "" {
		body["system"] = r.System
	}
	if !oldClaude.MatchString(r.Model) {
		display := "omitted"
		if r.ShowThinking {
			display = "summarized"
		}
		body["thinking"] = obj{"type": "adaptive", "display": display}
	}
	if r.Effort != "" && r.Effort != "default" {
		body["output_config"] = obj{"effort": r.Effort}
	}
	if r.Provider.Fallbacks {
		body["fallbacks"] = "default"
	}
	return r.Provider.base() + "/messages", body
}

func openaiRequest(r SendRequest, images map[string]string) (string, obj) {
	messages := []obj{}
	if r.System != "" {
		messages = append(messages, obj{"role": "system", "content": r.System})
	}
	for _, t := range turns(r.Messages) {
		if t.role == "assistant" {
			texts := make([]string, len(t.parts))
			for i, p := range t.parts {
				texts[i] = p.Text
			}
			messages = append(messages, obj{"role": "assistant", "content": strings.Join(texts, "\n\n")})
			continue
		}
		attached, text := t.images(images), t.text()
		if len(attached) == 0 {
			messages = append(messages, obj{"role": "user", "content": text})
			continue
		}
		content := []any{}
		for _, img := range attached {
			content = append(content, obj{"type": "image_url", "image_url": obj{"url": "data:" + img.mime + ";base64," + img.data}})
		}
		if text != "" {
			content = append(content, obj{"type": "text", "text": text})
		}
		messages = append(messages, obj{"role": "user", "content": content})
	}
	body := obj{"model": r.Model, "stream": true, "messages": messages}
	// OpenAI's reasoning models reject max_tokens; the servers that copy
	// its API mostly only know max_tokens
	if official.MatchString(r.Provider.BaseURL) {
		body["max_completion_tokens"] = r.MaxTokens
	} else {
		body["max_tokens"] = r.MaxTokens
	}
	// Chat Completions tops out at "high"
	switch r.Effort {
	case "", "default":
	case "xhigh", "max":
		body["reasoning_effort"] = "high"
	default:
		body["reasoning_effort"] = r.Effort
	}
	return r.Provider.base() + "/chat/completions", body
}

func geminiRequest(r SendRequest, images map[string]string) (string, obj) {
	contents := []obj{}
	for _, t := range turns(r.Messages) {
		if t.role == "assistant" {
			texts := make([]string, len(t.parts))
			for i, p := range t.parts {
				texts[i] = p.Text
			}
			contents = append(contents, obj{"role": "model", "parts": []any{obj{"text": strings.Join(texts, "\n\n")}}})
			continue
		}
		parts := []any{}
		for _, img := range t.images(images) {
			parts = append(parts, obj{"inline_data": obj{"mime_type": img.mime, "data": img.data}})
		}
		if text := t.text(); text != "" || len(parts) == 0 {
			parts = append(parts, obj{"text": orSpace(text)})
		}
		contents = append(contents, obj{"role": "user", "parts": parts})
	}
	body := obj{
		"contents":         contents,
		"generationConfig": obj{"maxOutputTokens": r.MaxTokens, "thinkingConfig": obj{"includeThoughts": r.ShowThinking}},
	}
	if r.System != "" {
		body["systemInstruction"] = obj{"parts": []any{obj{"text": r.System}}}
	}
	return r.Provider.base() + "/models/" + url.PathEscape(r.Model) + ":streamGenerateContent?alt=sse", body
}

// -- Streams --

// stream is a reply as its SSE events arrive
type stream struct {
	kind, model, stopReason, err string
	// Anthropic's content blocks, by index
	blocks []map[string]any
}

// parse reads one `data:` payload and returns what to show
func (st *stream) parse(data string) []Delta {
	if data == "[DONE]" {
		return nil
	}
	var head struct {
		Error json.RawMessage `json:"error"`
	}
	if json.Unmarshal([]byte(data), &head) != nil {
		return nil
	}
	if len(head.Error) > 0 && string(head.Error) != "null" {
		var e struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(head.Error, &e) == nil && e.Message != "" {
			st.err = e.Message
		} else {
			st.err = string(head.Error)
		}
		return nil
	}
	switch st.kind {
	case "anthropic":
		return st.anthropic(data)
	case "gemini":
		return st.gemini(data)
	}
	return st.openai(data)
}

func delta(out []Delta, kind, text string) []Delta {
	if text == "" {
		return out
	}
	return append(out, Delta{Kind: kind, Text: text})
}

func (st *stream) anthropic(data string) []Delta {
	var e struct {
		Type    string `json:"type"`
		Index   int    `json:"index"`
		Message struct {
			Model string `json:"model"`
		} `json:"message"`
		ContentBlock map[string]any `json:"content_block"`
		Delta        struct {
			Type       string `json:"type"`
			Text       string `json:"text"`
			Thinking   string `json:"thinking"`
			Signature  string `json:"signature"`
			StopReason string `json:"stop_reason"`
		} `json:"delta"`
	}
	if json.Unmarshal([]byte(data), &e) != nil || e.Index < 0 || e.Index > 1000 {
		return nil
	}
	block := func() map[string]any {
		for len(st.blocks) <= e.Index {
			st.blocks = append(st.blocks, nil)
		}
		if st.blocks[e.Index] == nil {
			st.blocks[e.Index] = map[string]any{}
		}
		return st.blocks[e.Index]
	}
	appendTo := func(b map[string]any, key, s string) {
		prev, _ := b[key].(string)
		b[key] = prev + s
	}
	var out []Delta
	switch e.Type {
	case "message_start":
		if e.Message.Model != "" {
			st.model = e.Message.Model
		}
	case "content_block_start":
		b := block()
		clear(b)
		for k, v := range e.ContentBlock {
			b[k] = v
		}
	case "content_block_delta":
		b := block()
		switch e.Delta.Type {
		case "text_delta":
			appendTo(b, "text", e.Delta.Text)
			out = delta(out, "text", e.Delta.Text)
		case "thinking_delta":
			appendTo(b, "thinking", e.Delta.Thinking)
			out = delta(out, "thinking", e.Delta.Thinking)
		case "signature_delta":
			appendTo(b, "signature", e.Delta.Signature)
		}
	case "message_delta":
		if e.Delta.StopReason != "" {
			st.stopReason = e.Delta.StopReason
		}
	}
	return out
}

func (st *stream) openai(data string) []Delta {
	var e struct {
		Model   string `json:"model"`
		Choices []struct {
			Delta struct {
				Content          string  `json:"content"`
				ReasoningContent *string `json:"reasoning_content"`
				Reasoning        string  `json:"reasoning"`
			} `json:"delta"`
			FinishReason string `json:"finish_reason"`
		} `json:"choices"`
	}
	if json.Unmarshal([]byte(data), &e) != nil {
		return nil
	}
	if e.Model != "" {
		st.model = e.Model
	}
	if len(e.Choices) == 0 {
		return nil
	}
	c := e.Choices[0]
	reasoning := c.Delta.Reasoning
	if c.Delta.ReasoningContent != nil {
		reasoning = *c.Delta.ReasoningContent
	}
	out := delta(nil, "thinking", reasoning)
	out = delta(out, "text", c.Delta.Content)
	if c.FinishReason != "" {
		st.stopReason = c.FinishReason
	}
	return out
}

func (st *stream) gemini(data string) []Delta {
	var e struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text    string `json:"text"`
					Thought bool   `json:"thought"`
				} `json:"parts"`
			} `json:"content"`
			FinishReason string `json:"finishReason"`
		} `json:"candidates"`
	}
	if json.Unmarshal([]byte(data), &e) != nil || len(e.Candidates) == 0 {
		return nil
	}
	c := e.Candidates[0]
	var out []Delta
	for _, p := range c.Content.Parts {
		kind := "text"
		if p.Thought {
			kind = "thinking"
		}
		out = delta(out, kind, p.Text)
	}
	if c.FinishReason != "" {
		st.stopReason = c.FinishReason
	}
	return out
}
