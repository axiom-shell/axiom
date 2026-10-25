package claudeusage

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"
	"time"
)

const okReply = `{
	"five_hour": {"utilization": 12.4, "resets_at": "2026-10-25T14:00:00Z"},
	"seven_day": {"utilization": 40.6, "resets_at": "2026-10-28T16:00:00Z"},
	"seven_day_opus": null,
	"extra_usage": {"is_enabled": true, "used_credits": 3.5, "monthly_limit": 50, "utilization": 7, "currency": "USD"},
	"seven_day_breakdown": {"rows": [{"display_name": "Claude Code", "percent": 97}, {"key": "chat", "percent": 3}, {"key": "idle", "percent": 0}]}
}`

// server answers with the queued replies in order, then the last again
type server struct {
	mu      sync.Mutex
	replies []reply
	tokens  []string
	*httptest.Server
}

type reply struct {
	status     int
	retryAfter string
	body       string
}

func newServer(t *testing.T, replies ...reply) *server {
	s := &server{replies: replies}
	s.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		s.tokens = append(s.tokens, r.Header.Get("Authorization"))
		rep := s.replies[0]
		if len(s.replies) > 1 {
			s.replies = s.replies[1:]
		}
		if rep.retryAfter != "" {
			w.Header().Set("Retry-After", rep.retryAfter)
		}
		w.WriteHeader(rep.status)
		w.Write([]byte(rep.body))
	}))
	t.Cleanup(s.Close)
	return s
}

func (s *server) calls() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.tokens)
}

type clock struct{ now time.Time }

func (c *clock) Now() time.Time { return c.now }

// account is a Claude Code config dir logged in with token
func account(t *testing.T, token string, expiresAt time.Time) string {
	dir := t.TempDir()
	creds := map[string]any{"claudeAiOauth": map[string]any{"accessToken": token, "expiresAt": expiresAt.UnixMilli(), "subscriptionType": "max"}}
	writeJSON(t, filepath.Join(dir, ".credentials.json"), creds)
	writeJSON(t, filepath.Join(dir, ".claude.json"), map[string]any{"oauthAccount": map[string]any{"organizationName": "Org"}})
	return dir
}

func writeJSON(t *testing.T, path string, v any) {
	data, _ := json.Marshal(v)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
}

type harness struct {
	t     *testing.T
	srv   *server
	clock *clock
	fetch func(ctx context.Context, requests []json.RawMessage) (any, error)
	src   func()
	state string
}

func newHarness(t *testing.T, replies ...reply) *harness {
	h := &harness{t: t, srv: newServer(t, replies...), clock: &clock{time.UnixMilli(1_000_000_000)}, state: filepath.Join(t.TempDir(), "state", "claude-usage.json")}
	h.restart()
	return h
}

// restart is a new source on the same state file (axiom restarted)
func (h *harness) restart() {
	src := Source(Options{StateFile: h.state, Endpoint: h.srv.URL, Client: h.srv.Client(), Now: h.clock.Now})
	h.fetch, h.src = src.Fetch, src.OnRefresh
}

func (h *harness) get(dir string, every time.Duration) Account {
	h.t.Helper()
	req, _ := json.Marshal(map[string]any{"interval": 60000, "every": every.Milliseconds(), "accounts": []map[string]string{{"label": "Work", "dir": dir}}})
	out, err := h.fetch(context.Background(), []json.RawMessage{req})
	if err != nil {
		h.t.Fatal(err)
	}
	a, ok := out.(map[string]Account)[dir]
	if !ok {
		h.t.Fatalf("no state for %s in %v", dir, out)
	}
	return a
}

func TestFetchesAndParses(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", okReply})
	dir := account(t, "tok", time.Time{})
	a := h.get(dir, 5*time.Minute)
	want := Account{
		Label: "Work", Dir: dir, Org: "Org", Plan: "max", Status: "ok", FetchedAt: 1_000_000_000,
		Session:   &Window{12, "2026-10-25T14:00:00Z"},
		Weekly:    &Window{41, "2026-10-28T16:00:00Z"},
		Extra:     &Extra{Used: 3.5, Limit: 50, Percent: 7, Currency: "USD"},
		Breakdown: []Share{{"Claude Code", 97}, {"chat", 3}},
	}
	if !reflect.DeepEqual(a, want) {
		t.Errorf("got  %+v\nwant %+v", a, want)
	}
	if h.srv.tokens[0] != "Bearer tok" {
		t.Errorf("sent %q", h.srv.tokens[0])
	}
}

// The newer `limits` shape stands in for missing windows
func TestLimitsFallback(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", `{"limits": [{"kind": "session", "percent": 55, "resets_at": "x"}, {"kind": "weekly_all", "percent": 20}]}`})
	a := h.get(account(t, "tok", time.Time{}), 5*time.Minute)
	if !reflect.DeepEqual(a.Session, &Window{55, "x"}) || !reflect.DeepEqual(a.Weekly, &Window{20, ""}) || a.WeeklyOpus != nil {
		t.Errorf("got %+v %+v", a.Session, a.Weekly)
	}
}

func TestOncePerIntervalAcrossRestarts(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", okReply})
	dir := account(t, "tok", time.Time{})
	h.get(dir, 5*time.Minute)
	h.clock.now = h.clock.now.Add(time.Minute)
	h.get(dir, 5*time.Minute)
	h.restart()
	h.clock.now = h.clock.now.Add(time.Minute)
	if a := h.get(dir, 5*time.Minute); a.Status != "ok" || a.Session == nil {
		t.Errorf("the saved numbers weren't kept: %+v", a)
	}
	if n := h.srv.calls(); n != 1 {
		t.Fatalf("%d fetches within the interval, want 1", n)
	}
	h.clock.now = h.clock.now.Add(3 * time.Minute)
	h.get(dir, 5*time.Minute)
	if n := h.srv.calls(); n != 2 {
		t.Errorf("%d fetches, want 2 once the interval passed", n)
	}
}

func TestLoginStates(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", okReply})
	empty := t.TempDir()
	if a := h.get(empty, 5*time.Minute); a.Status != "missing" || a.Error == "" {
		t.Errorf("no login: %+v", a)
	}
	expired := account(t, "tok", h.clock.now.Add(-time.Hour))
	if a := h.get(expired, 5*time.Minute); a.Status != "expired" {
		t.Errorf("expired token: %+v", a)
	}
	if h.srv.calls() != 0 {
		t.Errorf("asked without a usable token")
	}
	// Claude Code refreshes the token: fetched at the next tick, not the
	// next interval
	h.clock.now = h.clock.now.Add(time.Minute)
	writeJSON(t, filepath.Join(expired, ".credentials.json"), map[string]any{"claudeAiOauth": map[string]any{"accessToken": "new", "expiresAt": h.clock.now.Add(time.Hour).UnixMilli()}})
	os.Chtimes(filepath.Join(expired, ".credentials.json"), h.clock.now, h.clock.now.Add(time.Second))
	if a := h.get(expired, time.Hour); a.Status != "ok" || h.srv.tokens[0] != "Bearer new" {
		t.Errorf("a renewed login wasn't fetched: %+v", a)
	}
}

func TestUnauthorizedIsExpired(t *testing.T) {
	t.Parallel()
	for _, rep := range []reply{{401, "", ``}, {400, "", `{"error": {"type": "authentication_error", "message": "x"}}`}} {
		h := newHarness(t, rep)
		if a := h.get(account(t, "tok", time.Time{}), 5*time.Minute); a.Status != "expired" || a.Error != "" {
			t.Errorf("%d: %+v", rep.status, a)
		}
	}
}

func TestBackoff(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name        string
		replies     []reply
		wantErr     string
		waits       []time.Duration // RetryAt after each failure
		rateLimited bool
	}{
		{"server error doubles", []reply{{500, "", `{"error": {"message": "overloaded"}}`}}, "overloaded",
			[]time.Duration{5 * time.Minute, 10 * time.Minute, 20 * time.Minute, 40 * time.Minute, time.Hour, time.Hour}, false},
		{"429 waits five minutes at least", []reply{{429, "", ``}}, "HTTP 429",
			[]time.Duration{5 * time.Minute, 10 * time.Minute}, true},
		{"Retry-After is honoured", []reply{{429, "7200", ``}}, "HTTP 429",
			[]time.Duration{2 * time.Hour}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			h := newHarness(t, tc.replies...)
			dir := account(t, "tok", time.Time{})
			for i, wait := range tc.waits {
				a := h.get(dir, 5*time.Minute)
				if a.Status != "error" || a.Error != tc.wantErr || a.Failures != i+1 || a.RateLimited != tc.rateLimited {
					t.Fatalf("failure %d: %+v", i+1, a)
				}
				if got := time.Duration(a.RetryAt-h.clock.now.UnixMilli()) * time.Millisecond; got != wait {
					t.Fatalf("failure %d waits %v, want %v", i+1, got, wait)
				}
				// Not before RetryAt, even when asked
				h.clock.now = h.clock.now.Add(wait - time.Second)
				if tc.rateLimited {
					h.src()
				}
				before := h.srv.calls()
				h.get(dir, 5*time.Minute)
				if h.srv.calls() != before {
					t.Fatalf("fetched before RetryAt")
				}
				h.clock.now = h.clock.now.Add(time.Second)
			}
		})
	}
}

func TestRefreshFetchesNow(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", okReply})
	dir := account(t, "tok", time.Time{})
	h.get(dir, time.Hour)
	h.src()
	h.get(dir, time.Hour)
	if n := h.srv.calls(); n != 2 {
		t.Errorf("%d fetches, want 2", n)
	}
}

// Relative dirs (unexpanded ~) are never read
func TestRelativeDirsIgnored(t *testing.T) {
	t.Parallel()
	h := newHarness(t, reply{200, "", okReply})
	out, _ := h.fetch(context.Background(), []json.RawMessage{json.RawMessage(`{"accounts": [{"dir": "~/.claude"}]}`)})
	if len(out.(map[string]Account)) != 0 {
		t.Errorf("got %v", out)
	}
}
