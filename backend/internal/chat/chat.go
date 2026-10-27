// Package chat is the chat's side effects (ChatManager): the providers'
// HTTP APIs (Anthropic's Messages, OpenAI's Chat Completions and the
// servers copying it, Gemini's generateContent), built from the
// conversation with its images read by path and streamed back as deltas
// (send.go), their model lists, and the API keys they take. A key is
// read here, from the environment or package secrets (keys.go), so it
// never passes through QML, argv or a file of its own.
package chat

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
)

const (
	connectTimeout = 15 * time.Second
	// A models list; a reply streams for as long as it takes
	listTimeout = 30 * time.Second
	maxErrBody  = 1 << 20
	maxListBody = 8 << 20
)

// Options are where keys come from and how requests go; zero values are
// the real ones (only Secrets must be given).
type Options struct {
	// Secrets holds the stored keys
	Secrets *secrets.Store
	// Command's Env is where a provider's keyEnv is read (nil Env: the
	// daemon's own)
	Command func() command.Options
	Client  *http.Client
	Log     *slog.Logger
}

// Service answers the chat methods.
type Service struct {
	o       Options
	mu      sync.Mutex
	running map[string]context.CancelCauseFunc // replies streaming, by id, for Stop
}

// New makes the service.
func New(o Options) *Service {
	if o.Command == nil {
		o.Command = func() command.Options { return command.Options{} }
	}
	if o.Client == nil {
		dialer := &net.Dialer{Timeout: connectTimeout}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.DialContext = dialer.DialContext
		o.Client = &http.Client{Transport: transport}
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Service{o: o, running: map[string]context.CancelCauseFunc{}}
}

// Provider is a Chat.providers entry, as the shell sends it (never with a
// key).
type Provider struct {
	ID      string `json:"id"`
	Name    string `json:"name,omitempty"`
	Kind    string `json:"kind,omitempty"` // "anthropic", "openai" or "gemini"
	BaseURL string `json:"baseUrl,omitempty"`
	Auth    string `json:"auth,omitempty"`   // "none": no key
	KeyEnv  string `json:"keyEnv,omitempty"` // the variable a key is read from first
	// Anthropic's server-side fallback to another model when one is
	// overloaded
	Fallbacks bool `json:"fallbacks,omitempty"`
}

func (p Provider) label() string {
	if p.Name != "" {
		return p.Name
	}
	return p.ID
}

// official is OpenAI's own API, which lists more than chat models and
// takes max_completion_tokens
var official = regexp.MustCompile(`(^|//)api\.openai\.com`)

func (p Provider) base() string { return strings.TrimRight(p.BaseURL, "/") }

// header sets the key's header for the provider's kind
func (p Provider) header(h http.Header, key string) {
	switch p.Kind {
	case "anthropic":
		h.Set("anthropic-version", "2023-06-01")
		h.Set("x-api-key", key)
	case "gemini":
		h.Set("x-goog-api-key", key)
	default:
		if p.Auth != "none" {
			h.Set("Authorization", "Bearer "+key)
		}
	}
}

// keyFor is the provider's key, or a not_found error naming it when it
// needs one and has none
func (s *Service) keyFor(ctx context.Context, p Provider) (string, error) {
	key, source, err := s.key(ctx, p)
	if err != nil {
		return "", err
	}
	if source == secrets.SourceNone {
		return "", axerr.New(axerr.NotFound, "no API key for %s", p.label())
	}
	return key, nil
}

// ModelsRequest is the provider to list the models of.
type ModelsRequest struct {
	Provider Provider `json:"provider"`
}

// ModelsResult is its chat models; null when the address didn't answer
// with a models list (not that kind of API).
type ModelsResult struct {
	Models []string `json:"models"`
}

// Models lists the provider's chat models: a test of its address and key
// both.
func (s *Service) Models(ctx context.Context, r ModelsRequest) (ModelsResult, error) {
	p := r.Provider
	key, err := s.keyFor(ctx, p)
	if err != nil {
		return ModelsResult{}, err
	}
	target := p.base() + "/models"
	switch p.Kind {
	case "anthropic":
		target += "?limit=1000"
	case "gemini":
		target += "?pageSize=1000"
	}
	ctx, cancel := context.WithTimeout(ctx, listTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return ModelsResult{}, axerr.Wrap(axerr.BadRequest, err, "the address of %s", p.label())
	}
	p.header(req.Header, key)
	resp, err := s.o.Client.Do(req)
	if err != nil {
		return ModelsResult{}, transportError(err)
	}
	defer resp.Body.Close()
	if err := statusError(resp); err != nil {
		return ModelsResult{}, err
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxListBody))
	if err != nil {
		return ModelsResult{}, transportError(err)
	}
	return ModelsResult{Models: chatModels(p, parseModels(p.Kind, body))}, nil
}

// parseModels is the model ids in a models list, nil when it isn't one
func parseModels(kind string, body []byte) []string {
	ids := []string{}
	if kind == "gemini" {
		var list struct {
			Models []struct {
				Name    string   `json:"name"`
				Methods []string `json:"supportedGenerationMethods"`
			} `json:"models"`
		}
		if json.Unmarshal(body, &list) != nil || list.Models == nil {
			return nil
		}
		for _, m := range list.Models {
			for _, method := range m.Methods {
				if method == "generateContent" {
					ids = append(ids, strings.TrimPrefix(m.Name, "models/"))
					break
				}
			}
		}
		return ids
	}
	var list struct {
		Data []struct {
			ID any `json:"id"`
		} `json:"data"`
	}
	if json.Unmarshal(body, &list) != nil || list.Data == nil {
		return nil
	}
	for _, m := range list.Data {
		if id, ok := m.ID.(string); ok {
			ids = append(ids, id)
		}
	}
	return ids
}

var (
	openaiChat    = regexp.MustCompile(`^(gpt-|o\d|chatgpt)`)
	openaiNotChat = regexp.MustCompile(`audio|realtime|tts|transcribe|image|search|embedding|moderation|instruct`)
)

// chatModels is the ids worth offering for chat: OpenAI's own list also
// holds embedding, speech, image and moderation models
func chatModels(p Provider, ids []string) []string {
	if ids == nil || !official.MatchString(p.BaseURL) {
		return ids
	}
	out := []string{}
	for _, id := range ids {
		if openaiChat.MatchString(id) && !openaiNotChat.MatchString(id) {
			out = append(out, id)
		}
	}
	return out
}

// transportError is a request that got no answer: unavailable, with the
// cause but not the URL
func transportError(err error) error {
	var uerr *url.Error
	if errors.As(err, &uerr) {
		err = uerr.Err
	}
	return axerr.Wrap(axerr.Unavailable, err, "no answer")
}

// statusError is an answer that isn't a 2xx: unauthorized for 401 and
// 403, else bad_reply, the message "<status>: <the body's message>"
func statusError(resp *http.Response) error {
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, maxErrBody))
	message := errorMessage(body)
	if message == "" {
		message = http.StatusText(resp.StatusCode)
	}
	kind := axerr.BadReply
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		kind = axerr.Unauthorized
	}
	return axerr.New(kind, "%d: %s", resp.StatusCode, message)
}

// errorMessage is the message in an error body (JSON or not)
func errorMessage(body []byte) string {
	trimmed := strings.TrimSpace(string(body))
	var parsed any
	if json.Unmarshal([]byte(trimmed), &parsed) != nil {
		return trimmed
	}
	if list, ok := parsed.([]any); ok && len(list) > 0 {
		parsed = list[0]
	}
	obj, ok := parsed.(map[string]any)
	if !ok {
		return trimmed
	}
	switch e := obj["error"].(type) {
	case string:
		return e
	case map[string]any:
		if m, ok := e["message"].(string); ok {
			return m
		}
		raw, _ := json.Marshal(e)
		return string(raw)
	}
	if m, ok := obj["message"].(string); ok {
		return m
	}
	return trimmed
}
