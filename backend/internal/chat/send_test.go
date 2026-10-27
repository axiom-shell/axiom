package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// conversation is a chat with an image, two user turns in a row, a
// finished reply with its thinking block, an unfinished one and a notice
func conversation(image string) []Message {
	return []Message{
		{Role: "user", Text: "first", Attachments: []Attachment{{Path: image, Mime: "image/png"}}},
		{Role: "user", Text: "again"},
		{Role: "assistant", Text: "reply", State: "done", Provider: "p", Model: "claude-x", Blocks: []map[string]any{
			{"type": "thinking", "thinking": "hm", "signature": "sig"},
			{"type": "text", "text": "reply"},
		}},
		{Role: "assistant", State: "streaming"},
		{Role: "system", Text: "notice"},
		{Role: "user", Text: "next"},
	}
}

func request(kind, model string, extra func(*SendRequest)) SendRequest {
	r := SendRequest{
		ID: "r1", Provider: Provider{ID: "p", Kind: kind, BaseURL: "https://example.test/v1/"}, Model: model,
		Messages: conversation("/img/a.png"), System: "be brief", MaxTokens: 100, Effort: "max", ShowThinking: true,
	}
	if extra != nil {
		extra(&r)
	}
	return r
}

// roundTrip is the body as the provider reads it
func roundTrip(t *testing.T, body obj) map[string]any {
	t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	json.Unmarshal(raw, &out)
	return out
}

// get walks a path of keys and indexes into decoded JSON
func get(v any, path ...any) any {
	for _, p := range path {
		switch k := p.(type) {
		case string:
			m, _ := v.(map[string]any)
			v = m[k]
		case int:
			l, _ := v.([]any)
			if k >= len(l) {
				return nil
			}
			v = l[k]
		}
	}
	return v
}

func roles(v any, key string) []string {
	var out []string
	for _, m := range v.([]any) {
		out = append(out, m.(map[string]any)[key].(string))
	}
	return out
}

func TestBuild(t *testing.T) {
	t.Parallel()
	images := map[string]string{"/img/a.png": "QUJD"}
	type check struct {
		path []any
		want any
	}
	tests := []struct {
		name   string
		req    SendRequest
		url    string
		roles  []string
		checks []check
	}{
		{"anthropic", request("anthropic", "claude-x", func(r *SendRequest) { r.Provider.Fallbacks = true }), "https://example.test/v1/messages",
			[]string{"user", "assistant", "user"}, []check{
				{[]any{"system"}, "be brief"}, {[]any{"max_tokens"}, 100.0}, {[]any{"output_config", "effort"}, "max"},
				{[]any{"thinking", "display"}, "summarized"}, {[]any{"fallbacks"}, "default"},
				{[]any{"messages", 0, "content", 0, "source", "data"}, "QUJD"},
				{[]any{"messages", 0, "content", 1, "text"}, "first\n\nagain"},
				// The model that wrote the thinking block gets it back
				{[]any{"messages", 1, "content", 0, "signature"}, "sig"},
				{[]any{"messages", 1, "content", 1, "type"}, "text"},
			}},
		{"anthropic, another model", request("anthropic", "claude-y", nil), "https://example.test/v1/messages",
			[]string{"user", "assistant", "user"}, []check{
				{[]any{"messages", 1, "content"}, []any{map[string]any{"type": "text", "text": "reply"}}},
			}},
		{"anthropic, an old model", request("anthropic", "claude-3-opus", func(r *SendRequest) { r.Effort = "default" }), "https://example.test/v1/messages",
			[]string{"user", "assistant", "user"}, []check{{[]any{"thinking"}, nil}, {[]any{"output_config"}, nil}}},
		{"openai", request("openai", "gpt", nil), "https://example.test/v1/chat/completions",
			[]string{"system", "user", "assistant", "user"}, []check{
				{[]any{"messages", 1, "content", 0, "image_url", "url"}, "data:image/png;base64,QUJD"},
				{[]any{"messages", 2, "content"}, "reply"}, {[]any{"max_tokens"}, 100.0}, {[]any{"reasoning_effort"}, "high"},
			}},
		{"openai's own", request("openai", "gpt", func(r *SendRequest) { r.Provider.BaseURL = "https://api.openai.com/v1" }), "https://api.openai.com/v1/chat/completions",
			[]string{"system", "user", "assistant", "user"}, []check{{[]any{"max_completion_tokens"}, 100.0}, {[]any{"max_tokens"}, nil}}},
		{"gemini", request("gemini", "gemini pro", nil), "https://example.test/v1/models/gemini%20pro:streamGenerateContent?alt=sse",
			nil, []check{
				{[]any{"contents", 0, "parts", 0, "inline_data", "data"}, "QUJD"},
				{[]any{"contents", 1, "role"}, "model"},
				{[]any{"systemInstruction", "parts", 0, "text"}, "be brief"},
				{[]any{"generationConfig", "thinkingConfig", "includeThoughts"}, true},
			}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			url, body := build(tc.req, images)
			if url != tc.url {
				t.Errorf("url %q, want %q", url, tc.url)
			}
			b := roundTrip(t, body)
			if tc.roles != nil {
				if got := roles(b["messages"], "role"); !reflect.DeepEqual(got, tc.roles) {
					t.Errorf("roles %v, want %v", got, tc.roles)
				}
			}
			for _, c := range tc.checks {
				if got := get(b, c.path...); !reflect.DeepEqual(got, c.want) {
					t.Errorf("%v: got %#v, want %#v", c.path, got, c.want)
				}
			}
		})
	}
}

func TestStreams(t *testing.T) {
	t.Parallel()
	tests := []struct {
		kind       string
		events     []string
		deltas     string // kind:text, …
		model      string
		stopReason string
		blocks     []map[string]any
		err        string
	}{
		{"anthropic", []string{
			`{"type": "message_start", "message": {"model": "claude-x"}}`,
			`{"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}}`,
			`{"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "hmm"}}`,
			`{"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "abc"}}`,
			`{"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}}`,
			`{"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "Hel"}}`,
			`{"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "lo"}}`,
			`{"type": "message_delta", "delta": {"stop_reason": "end_turn"}}`,
			`{"type": "message_stop"}`,
		}, "thinking:hmm,text:Hel,text:lo", "claude-x", "end_turn", []map[string]any{
			{"type": "thinking", "thinking": "hmm", "signature": "abc"},
			{"type": "text", "text": "Hello"},
		}, ""},
		{"openai", []string{
			`{"model": "gpt-x", "choices": [{"delta": {"reasoning_content": "think"}}]}`,
			`{"choices": [{"delta": {"content": "Hi"}, "finish_reason": "length"}]}`,
			`{"choices": [], "usage": {"total_tokens": 3}}`,
			`[DONE]`,
		}, "thinking:think,text:Hi", "gpt-x", "length", nil, ""},
		{"gemini", []string{
			`{"candidates": [{"content": {"parts": [{"text": "plan", "thought": true}, {"text": "Answer"}]}}]}`,
			`{"candidates": [{"finishReason": "SAFETY"}], "modelVersion": "other"}`,
		}, "thinking:plan,text:Answer", "start", "SAFETY", nil, ""},
		{"anthropic", []string{`not json`, `{"type": "error", "error": {"message": "overloaded"}}`}, "", "start", "", nil, "overloaded"},
	}
	for _, tc := range tests {
		st := &stream{kind: tc.kind, model: "start"}
		var deltas []string
		for _, e := range tc.events {
			for _, d := range st.parse(e) {
				deltas = append(deltas, d.Kind+":"+d.Text)
			}
		}
		if got := strings.Join(deltas, ","); got != tc.deltas || st.model != tc.model || st.stopReason != tc.stopReason || st.err != tc.err {
			t.Errorf("%s: got %q %q %q %q", tc.kind, got, st.model, st.stopReason, st.err)
		}
		if tc.blocks != nil && !reflect.DeepEqual(st.blocks, tc.blocks) {
			t.Errorf("%s: blocks %v", tc.kind, st.blocks)
		}
	}
	if stopNotice("SAFETY") != "refusal" || stopNotice("length") != "length" || stopNotice("end_turn") != "" {
		t.Error("stopNotice")
	}
}

// A reply over HTTP: the key and the image read by axiom, the deltas
// pushed as they stream, the result at the end
func TestSend(t *testing.T) {
	t.Parallel()
	image := filepath.Join(t.TempDir(), "a.png")
	os.WriteFile(image, []byte("ABC"), 0o600)
	var asked map[string]any
	var key string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key = r.Header.Get("x-api-key")
		raw, _ := io.ReadAll(r.Body)
		json.Unmarshal(raw, &asked)
		for _, e := range []string{
			`{"type": "message_start", "message": {"model": "claude-x-1"}}`,
			`{"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}`,
			`{"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hi"}}`,
			`{"type": "message_delta", "delta": {"stop_reason": "max_tokens"}}`,
		} {
			fmt.Fprintf(w, "event: x\ndata: %s\n\n", e)
		}
	}))
	defer srv.Close()
	s := newService(t, map[string]string{"p": "the-key"}, []string{})
	r := request("anthropic", "claude-x", func(r *SendRequest) {
		r.Provider.BaseURL = srv.URL
		r.Messages = conversation(image)
	})
	var deltas []Delta
	res, err := s.Send(context.Background(), r, func(d Delta) { deltas = append(deltas, d) })
	if err != nil {
		t.Fatal(err)
	}
	want := SendResult{Model: "claude-x-1", Blocks: []map[string]any{{"type": "text", "text": "Hi"}}, Notice: "length"}
	if !reflect.DeepEqual(res, want) || !reflect.DeepEqual(deltas, []Delta{{ID: "r1", Kind: "text", Text: "Hi"}}) {
		t.Errorf("got %+v %+v", res, deltas)
	}
	if key != "the-key" || get(asked, "messages", 0, "content", 0, "source", "data") != "QUJD" {
		t.Errorf("sent key %q, body %v", key, asked)
	}
}

func TestSendErrors(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/denied/messages":
			w.WriteHeader(401)
			w.Write([]byte(`{"error": {"message": "bad key"}}`))
		case "/broken/messages":
			fmt.Fprint(w, "data: {\"type\": \"content_block_delta\", \"index\": 0, \"delta\": {\"type\": \"text_delta\", \"text\": \"so far\"}}\n\n")
			fmt.Fprint(w, "data: {\"type\": \"error\", \"error\": {\"message\": \"overloaded\"}}\n\n")
		case "/cut/messages":
			// The connection ends before the body it promised
			w.Header().Set("Content-Length", "1000")
			fmt.Fprint(w, "data: {\"type\": \"message_start\", \"message\": {}}\n\n")
		}
	}))
	defer srv.Close()
	s := newService(t, map[string]string{"p": "k"}, []string{})
	tests := []struct {
		base, id string
		kind     axerr.Kind
		message  string
	}{
		{srv.URL + "/denied", "p", axerr.Unauthorized, "401: bad key"},
		{srv.URL + "/broken", "p", axerr.BadReply, "overloaded"},
		{srv.URL + "/cut", "p", axerr.Unavailable, ""},
		{srv.URL, "nokey", axerr.NotFound, "no API key for nokey"},
		{"http://127.0.0.1:1", "p", axerr.Unavailable, ""},
	}
	for _, tc := range tests {
		r := request("anthropic", "claude-x", func(r *SendRequest) { r.Provider.BaseURL, r.Provider.ID = tc.base, tc.id })
		_, err := s.Send(context.Background(), r, func(Delta) {})
		var aerr *axerr.Error
		if !errors.As(err, &aerr) || aerr.Kind != tc.kind || (tc.message != "" && aerr.Message != tc.message) {
			t.Errorf("%s: got %v, want %s %q", tc.base, err, tc.kind, tc.message)
		}
	}
}

// Stop ends a reply mid-stream: not an error, and its id is forgotten
func TestStop(t *testing.T) {
	t.Parallel()
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "data: {\"choices\": [{\"delta\": {\"content\": \"part\"}}]}\n\n")
		w.(http.Flusher).Flush()
		select {
		case <-release:
		case <-r.Context().Done():
		}
	}))
	defer srv.Close()
	defer close(release)
	s := newService(t, nil, []string{})
	r := request("openai", "gpt", func(r *SendRequest) { r.Provider.BaseURL, r.Provider.Auth = srv.URL, "none" })
	var once sync.Once
	res, err := s.Send(context.Background(), r, func(Delta) { once.Do(func() { s.Stop("r1") }) })
	if err != nil || !res.Stopped || res.Model != "gpt" || len(res.Blocks) != 0 {
		t.Errorf("got %+v %v", res, err)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.running) != 0 {
		t.Errorf("still running: %v", s.running)
	}
}
