package chat

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/command"
)

// secretTool is one fake secret-tool for every test, written by TestMain
// before any test forks: a program written while another test forks
// can't be run ("text file busy"). It answers `lookup service axiom
// provider <id>` with the file <the path it ran as>.keys/<id> (exit 1
// without one), so each test links it with its own keyring.
var secretTool string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "chat-tools-")
	if err != nil {
		panic(err)
	}
	secretTool = filepath.Join(dir, "secret-tool")
	if err := os.WriteFile(secretTool, []byte("#!/bin/sh\nexec cat \"$0.keys/$5\" 2>/dev/null\n"), 0o755); err != nil {
		panic(err)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// fakeSecretTool is secretTool answering with keyring[id]
func fakeSecretTool(t *testing.T, keyring map[string]string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "secret-tool")
	if err := os.Symlink(secretTool, path); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(path+".keys", 0o700); err != nil {
		t.Fatal(err)
	}
	for id, key := range keyring {
		if err := os.WriteFile(filepath.Join(path+".keys", id), []byte(key+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return path
}

// newService is a service with keyring and file keys and env as the
// environment; the secrets file holds `file` under its id and a calendar
// password
func newService(t *testing.T, keyring map[string]string, env []string) *Service {
	t.Helper()
	dir := t.TempDir()
	secrets := `{"filed": " from-file ", "calendar:filed": "not this", "both": "file-loses"}`
	if err := os.WriteFile(filepath.Join(dir, "secrets.json"), []byte(secrets), 0o600); err != nil {
		t.Fatal(err)
	}
	return New(Options{
		StateDir:   dir,
		SecretTool: fakeSecretTool(t, keyring),
		Command:    func() command.Options { return command.Options{Env: env} },
	})
}

func TestKeySources(t *testing.T) {
	t.Parallel()
	s := newService(t, map[string]string{"ring": "from-ring", "both": "ring-wins"}, []string{"PATH=" + os.Getenv("PATH"), "MY_KEY=from-env"})
	tests := []struct {
		provider    Provider
		key, source string
	}{
		{Provider{ID: "ring", KeyEnv: "MY_KEY"}, "from-env", SourceEnv},
		{Provider{ID: "ring", KeyEnv: "UNSET_KEY"}, "from-ring", SourceKeyring},
		{Provider{ID: "both"}, "ring-wins", SourceKeyring},
		{Provider{ID: "filed"}, "from-file", SourceFile},
		{Provider{ID: "missing"}, "", SourceNone},
		{Provider{ID: "ring", Auth: "none", KeyEnv: "MY_KEY"}, "", SourceUnneeded},
	}
	for _, tc := range tests {
		key, source, err := s.key(context.Background(), tc.provider)
		if err != nil || key != tc.key || source != tc.source {
			t.Errorf("%+v: got %q %q %v, want %q %q", tc.provider, key, source, err, tc.key, tc.source)
		}
	}
	got, err := s.Status(context.Background(), StatusRequest{Providers: []Provider{{ID: "ring"}, {ID: "filed"}, {ID: "missing"}, {ID: "local", Auth: "none"}}})
	want := map[string]string{"ring": SourceKeyring, "filed": SourceFile, "missing": SourceNone, "local": SourceUnneeded}
	if err != nil || !reflect.DeepEqual(got.Statuses, want) {
		t.Errorf("Status: got %v %v, want %v", got.Statuses, err, want)
	}
}

// Without secret-tool installed the file still answers
func TestKeyWithoutSecretTool(t *testing.T) {
	t.Parallel()
	s := newService(t, nil, []string{})
	s.o.SecretTool = filepath.Join(t.TempDir(), "missing")
	if key, source, err := s.key(context.Background(), Provider{ID: "filed"}); key != "from-file" || source != SourceFile || err != nil {
		t.Errorf("got %q %q %v", key, source, err)
	}
}

func TestModels(t *testing.T) {
	t.Parallel()
	type seen struct{ path, query, header string }
	tests := []struct {
		name     string
		provider Provider
		reply    string
		want     []string
		seen     seen
	}{
		{"anthropic", Provider{ID: "ring", Kind: "anthropic"}, `{"data": [{"id": "claude-x"}]}`, []string{"claude-x"}, seen{"/v1/models", "limit=1000", "from-ring"}},
		{"gemini", Provider{ID: "ring", Kind: "gemini"},
			`{"models": [{"name": "models/g1", "supportedGenerationMethods": ["generateContent"]}, {"name": "models/embed"}]}`, []string{"g1"}, seen{"/v1/models", "pageSize=1000", "from-ring"}},
		{"openai", Provider{ID: "ring", Kind: "openai"}, `{"data": [{"id": "a"}, {"id": 3}]}`, []string{"a"}, seen{"/v1/models", "", "Bearer from-ring"}},
		{"no auth", Provider{ID: "local", Kind: "openai", Auth: "none"}, `{"data": []}`, []string{}, seen{"/v1/models", "", ""}},
		{"not an API", Provider{ID: "ring", Kind: "openai"}, `<html>`, nil, seen{"/v1/models", "", "Bearer from-ring"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var got seen
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				got = seen{r.URL.Path, r.URL.RawQuery, r.Header.Get("x-api-key") + r.Header.Get("x-goog-api-key") + r.Header.Get("Authorization")}
				w.Write([]byte(tc.reply))
			}))
			defer srv.Close()
			s := newService(t, map[string]string{"ring": "from-ring"}, []string{})
			tc.provider.BaseURL = srv.URL + "/v1/"
			res, err := s.Models(context.Background(), ModelsRequest{Provider: tc.provider})
			if err != nil || !reflect.DeepEqual(res.Models, tc.want) || got != tc.seen {
				t.Errorf("got %#v %v, asked %+v; want %#v, %+v", res.Models, err, got, tc.want, tc.seen)
			}
		})
	}
}

func TestModelsErrors(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/denied/models":
			w.WriteHeader(401)
			w.Write([]byte(`{"error": {"message": "bad key"}}`))
		default:
			w.WriteHeader(502)
			w.Write([]byte("  Bad Gateway \n"))
		}
	}))
	defer srv.Close()
	s := newService(t, map[string]string{"ring": "k"}, []string{})
	tests := []struct {
		provider Provider
		kind     axerr.Kind
		message  string
	}{
		{Provider{ID: "missing", Name: "Nobody", Kind: "openai", BaseURL: srv.URL}, axerr.NotFound, "no API key for Nobody"},
		{Provider{ID: "ring", Kind: "openai", BaseURL: srv.URL + "/denied"}, axerr.Unauthorized, "401: bad key"},
		{Provider{ID: "ring", Kind: "openai", BaseURL: srv.URL + "/down"}, axerr.BadReply, "502: Bad Gateway"},
		{Provider{ID: "ring", Kind: "openai", BaseURL: "http://127.0.0.1:1"}, axerr.Unavailable, ""},
	}
	for _, tc := range tests {
		_, err := s.Models(context.Background(), ModelsRequest{Provider: tc.provider})
		var aerr *axerr.Error
		if !errors.As(err, &aerr) || aerr.Kind != tc.kind || (tc.message != "" && aerr.Message != tc.message) {
			t.Errorf("%s: got %v, want %s %q", tc.provider.BaseURL, err, tc.kind, tc.message)
		}
	}
}

func TestChatModelsOnOpenAI(t *testing.T) {
	t.Parallel()
	official := Provider{BaseURL: "https://api.openai.com/v1"}
	got := chatModels(official, []string{"gpt-5", "text-embedding-3", "gpt-4o-audio", "o3"})
	if !reflect.DeepEqual(got, []string{"gpt-5", "o3"}) {
		t.Errorf("got %v", got)
	}
	if got := chatModels(Provider{BaseURL: "http://localhost"}, []string{"anything"}); !reflect.DeepEqual(got, []string{"anything"}) {
		t.Errorf("got %v", got)
	}
}

func TestErrorMessage(t *testing.T) {
	t.Parallel()
	for body, want := range map[string]string{
		`{"error": {"message": "bad key"}}`:  "bad key",
		`[{"error": {"message": "gemini"}}]`: "gemini",
		`{"error": "plain"}`:                 "plain",
		`{"message": "top"}`:                 "top",
		"  502 Bad Gateway \n":               "502 Bad Gateway",
	} {
		if got := errorMessage([]byte(body)); got != want {
			t.Errorf("%q: got %q, want %q", body, got, want)
		}
	}
}
