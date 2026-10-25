// Package claudeusage is Claude plan usage for the shell, the
// `claudeUsage` polled topic (ClaudeUsageManager): the numbers Claude
// Code's /usage shows for each Claude Code account (a CLAUDE_CONFIG_DIR),
// from api.anthropic.com/api/oauth/usage (undocumented, so parsed
// defensively) with the OAuth token in the dir's .credentials.json. The
// token is read here and never leaves the daemon. The credentials are
// only ever read: an expired token marks the account `expired`, keeping
// its last numbers, until Claude Code refreshes it.
//
// The endpoint rate limits hard, so each account is fetched at most once
// per interval (tracked across restarts in $XDG_STATE_HOME/axiom/
// claude-usage.json) and a failure backs off exponentially, honouring
// Retry-After on a 429. The topic ticks every minute to see what's due.
package claudeusage

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Endpoint is where usage comes from.
const Endpoint = "https://api.anthropic.com/api/oauth/usage"

const (
	minEvery     = time.Minute
	defaultEvery = 5 * time.Minute
	maxBackoff   = time.Hour
	// A 429 waits at least this long, whatever the interval
	rateLimitWait = 5 * time.Minute
	timeout       = 15 * time.Second
	maxBody       = 1 << 20
)

// Window is a usage window's share used and when it resets.
type Window struct {
	Percent  int    `json:"percent"`
	ResetsAt string `json:"resetsAt"`
}

// Extra is paid usage beyond the plan, when it's on.
type Extra struct {
	Used     float64 `json:"used"`
	Limit    float64 `json:"limit"`
	Percent  int     `json:"percent"`
	Currency string  `json:"currency"`
}

// Share is one row of the weekly breakdown.
type Share struct {
	Name    string `json:"name"`
	Percent int    `json:"percent"`
}

// Account is one account's state, as the shell shows it and as it's saved.
type Account struct {
	Label string `json:"label"`
	Dir   string `json:"dir"`
	Org   string `json:"org"`
	Plan  string `json:"plan"`
	// Status is "pending", "ok", "expired" (log in again in Claude Code),
	// "error" (Error says why) or "missing" (no login in Dir)
	Status       string  `json:"status"`
	Error        string  `json:"error"`
	FetchedAt    int64   `json:"fetchedAt"` // ms since the epoch, 0 never
	Session      *Window `json:"session"`
	Weekly       *Window `json:"weekly"`
	WeeklyOpus   *Window `json:"weeklyOpus"`
	WeeklySonnet *Window `json:"weeklySonnet"`
	Extra        *Extra  `json:"extra"`
	Breakdown    []Share `json:"breakdown"`
	// After a failure: not fetched again before RetryAt (ms)
	RetryAt     int64 `json:"retryAt"`
	Failures    int   `json:"failures"`
	RateLimited bool  `json:"rateLimited"`
}

type request struct {
	Every    *float64 `json:"every"` // ms: how often each account is fetched
	Accounts []struct {
		Label string `json:"label"`
		Dir   string `json:"dir"` // absolute (the shell expands ~)
	} `json:"accounts"`
}

// Options are where the source reads and writes; zero values are the
// real ones.
type Options struct {
	Log *slog.Logger
	// StateFile keeps the accounts across restarts ("" keeps nothing)
	StateFile string
	Endpoint  string
	Client    *http.Client
	Now       func() time.Time
}

// Source is the `claudeUsage` topic.
func Source(o Options) topics.Source {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Endpoint == "" {
		o.Endpoint = Endpoint
	}
	if o.Client == nil {
		o.Client = http.DefaultClient
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	u := &usage{o: o, creds: map[string]time.Time{}}
	return topics.Source{
		Name:      "claudeUsage",
		Floor:     time.Minute,
		Default:   time.Minute,
		OnRefresh: func() { u.forced.Store(true) },
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			return u.fetch(ctx, requests), nil
		},
	}
}

type usage struct {
	o      Options
	forced atomic.Bool
	// A loop stopped and started again can briefly overlap the old one
	mu       sync.Mutex
	loaded   bool
	accounts map[string]*Account
	// Each dir's .credentials.json mtime when last looked at
	creds map[string]time.Time
}

// fetch fetches what's due and returns the requested accounts (copies:
// the hub marshals them after the lock is released).
func (u *usage) fetch(ctx context.Context, requests []json.RawMessage) map[string]Account {
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.loaded {
		u.loaded = true
		u.load()
	}
	every := time.Duration(0)
	var dirs []string
	labels := map[string]string{}
	for _, raw := range requests {
		var r request
		if json.Unmarshal(raw, &r) != nil {
			continue
		}
		if r.Every != nil {
			if d := time.Duration(*r.Every * float64(time.Millisecond)); every == 0 || d < every {
				every = d
			}
		}
		for _, a := range r.Accounts {
			if !filepath.IsAbs(a.Dir) {
				continue
			}
			dir := filepath.Clean(a.Dir)
			if !slices.Contains(dirs, dir) {
				dirs = append(dirs, dir)
			}
			if labels[dir] == "" {
				labels[dir] = a.Label
			}
		}
	}
	if every == 0 {
		every = defaultEvery
	}
	every = max(every, minEvery)
	forced := u.forced.Swap(false)

	out := map[string]Account{}
	changed := false
	for _, dir := range dirs {
		label := labels[dir]
		if label == "" {
			label = filepath.Base(dir)
		}
		a := u.accounts[dir]
		if a == nil {
			a = &Account{Dir: dir, Status: "pending", Breakdown: []Share{}}
			u.accounts[dir] = a
			changed = true
		}
		if a.Label != label {
			a.Label, changed = label, true
		}
		now := u.o.Now()
		// Claude Code rewrote the credentials: an account whose login had
		// lapsed is fetched straight away (fresh numbers stay fresh with a
		// new token)
		renewed := u.credsChanged(dir) && (a.Status == "expired" || a.Status == "missing")
		limited := a.RateLimited && now.UnixMilli() < a.RetryAt
		if renewed || (forced && !limited) || due(a, now, every) {
			u.fetchOne(ctx, a, every)
			changed = true
		}
		out[dir] = *a
	}
	if changed {
		u.save()
	}
	return out
}

// due: not fetched within the interval and not backing off (after a
// restart, the saved numbers are still fresh)
func due(a *Account, now time.Time, every time.Duration) bool {
	ms := now.UnixMilli()
	return ms >= a.RetryAt && time.Duration(ms-a.FetchedAt)*time.Millisecond >= every*9/10
}

func (u *usage) credsChanged(dir string) bool {
	fi, err := os.Stat(filepath.Join(dir, ".credentials.json"))
	var mtime time.Time
	if err == nil {
		mtime = fi.ModTime()
	}
	prev, seen := u.creds[dir]
	u.creds[dir] = mtime
	return seen && !mtime.Equal(prev)
}

type credentials struct {
	ClaudeAiOauth *struct {
		AccessToken      string  `json:"accessToken"`
		ExpiresAt        float64 `json:"expiresAt"` // ms
		SubscriptionType string  `json:"subscriptionType"`
	} `json:"claudeAiOauth"`
}

func (u *usage) fetchOne(ctx context.Context, a *Account, every time.Duration) {
	var creds credentials
	readJSON(filepath.Join(a.Dir, ".credentials.json"), &creds)
	if a.Org == "" {
		var claude struct {
			OAuthAccount *struct {
				OrganizationName string `json:"organizationName"`
			} `json:"oauthAccount"`
		}
		if readJSON(filepath.Join(a.Dir, ".claude.json"), &claude) && claude.OAuthAccount != nil {
			a.Org = claude.OAuthAccount.OrganizationName
		}
	}
	oauth := creds.ClaudeAiOauth
	if oauth != nil && oauth.SubscriptionType != "" {
		a.Plan = oauth.SubscriptionType
	}
	now := u.o.Now()
	switch {
	case oauth == nil || oauth.AccessToken == "":
		a.Status, a.Error = "missing", "No Claude login in "+a.Dir
		return
	case oauth.ExpiresAt > 0 && int64(oauth.ExpiresAt) < now.UnixMilli():
		a.Status, a.Error = "expired", ""
		return
	}

	status, retryAfter, body, err := u.get(ctx, oauth.AccessToken)
	var reply map[string]any
	if json.Unmarshal(body, &reply) != nil {
		reply = nil
	}
	errObj, _ := reply["error"].(map[string]any)
	switch {
	case status == http.StatusUnauthorized || errObj["type"] == "authentication_error":
		a.Status, a.Error = "expired", ""
	case err == nil && status >= 200 && status < 300 && reply != nil:
		parse(a, reply)
		a.Status, a.Error = "ok", ""
		a.FetchedAt, a.RetryAt, a.Failures, a.RateLimited = now.UnixMilli(), 0, 0, false
	default:
		msg, _ := errObj["message"].(string)
		switch {
		case msg != "":
		case status != 0:
			msg = fmt.Sprintf("HTTP %d", status)
		case err != nil:
			msg = err.Error()
		}
		backoff(a, now, every, status == http.StatusTooManyRequests, retryAfter)
		a.Status, a.Error = "error", msg
		u.o.Log.Info("fetching Claude usage", "dir", a.Dir, "err", msg, "retry", time.UnixMilli(a.RetryAt).Sub(now).Round(time.Minute))
	}
}

// backoff doubles the wait per consecutive failure, up to an hour; a 429
// waits at least rateLimitWait and never less than its Retry-After.
func backoff(a *Account, now time.Time, every time.Duration, rateLimited bool, retryAfter time.Duration) {
	a.Failures++
	base := every
	if rateLimited {
		base = max(every, rateLimitWait)
	}
	delay := min(time.Duration(float64(base)*math.Pow(2, float64(a.Failures-1))), maxBackoff)
	delay = max(delay, retryAfter)
	a.RateLimited, a.RetryAt = rateLimited, now.Add(delay).UnixMilli()
}

// get asks the endpoint with token: its status (0 when there was no
// answer), Retry-After (in seconds; an HTTP date is ignored) and body.
func (u *usage) get(ctx context.Context, token string) (int, time.Duration, []byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.o.Endpoint, nil)
	if err != nil {
		return 0, 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("anthropic-beta", "oauth-2025-04-20")
	req.Header.Set("Accept", "application/json")
	resp, err := u.o.Client.Do(req)
	if err != nil {
		return 0, 0, nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	secs, _ := strconv.Atoi(resp.Header.Get("Retry-After"))
	return resp.StatusCode, time.Duration(max(secs, 0)) * time.Second, body, err
}

// parse reads the endpoint's answer into a.
func parse(a *Account, reply map[string]any) {
	a.Session = or(window(reply["five_hour"]), limit(reply, "session"))
	a.Weekly = or(window(reply["seven_day"]), limit(reply, "weekly_all"))
	a.WeeklyOpus = window(reply["seven_day_opus"])
	a.WeeklySonnet = window(reply["seven_day_sonnet"])
	a.Extra = nil
	if extra, _ := reply["extra_usage"].(map[string]any); extra["is_enabled"] == true {
		a.Extra = &Extra{
			Used:     number(extra["used_credits"]),
			Limit:    number(extra["monthly_limit"]),
			Percent:  round(number(extra["utilization"])),
			Currency: str(extra["currency"]),
		}
	}
	a.Breakdown = []Share{}
	breakdown, _ := reply["seven_day_breakdown"].(map[string]any)
	rows, _ := breakdown["rows"].([]any)
	for _, r := range rows {
		row, _ := r.(map[string]any)
		if p := number(row["percent"]); p > 0 {
			name := str(row["display_name"])
			if name == "" {
				name = str(row["key"])
			}
			a.Breakdown = append(a.Breakdown, Share{Name: name, Percent: round(p)})
		}
	}
}

func window(v any) *Window {
	w, _ := v.(map[string]any)
	if u, ok := w["utilization"].(float64); ok {
		return &Window{Percent: round(u), ResetsAt: str(w["resets_at"])}
	}
	return nil
}

func limit(reply map[string]any, kind string) *Window {
	limits, _ := reply["limits"].([]any)
	for _, l := range limits {
		m, _ := l.(map[string]any)
		if p, ok := m["percent"].(float64); ok && m["kind"] == kind {
			return &Window{Percent: round(p), ResetsAt: str(m["resets_at"])}
		}
	}
	return nil
}

func or(a, b *Window) *Window {
	if a != nil {
		return a
	}
	return b
}

func number(v any) float64 {
	f, _ := v.(float64)
	return f
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

func round(f float64) int { return int(math.Round(f)) }

func readJSON(path string, v any) bool {
	data, err := os.ReadFile(path)
	return err == nil && json.Unmarshal(data, v) == nil
}

func (u *usage) load() {
	u.accounts = map[string]*Account{}
	if u.o.StateFile != "" {
		readJSON(u.o.StateFile, &u.accounts)
	}
	for dir, a := range u.accounts {
		if a == nil {
			delete(u.accounts, dir)
		} else if a.Breakdown == nil {
			a.Breakdown = []Share{}
		}
	}
}

func (u *usage) save() {
	if u.o.StateFile == "" {
		return
	}
	data, err := json.MarshalIndent(u.accounts, "", "  ")
	if err == nil {
		err = os.MkdirAll(filepath.Dir(u.o.StateFile), 0o700)
	}
	if err == nil {
		err = fsx.WriteFile(u.o.StateFile, append(data, '\n'), 0o600)
	}
	if err != nil {
		u.o.Log.Warn("saving Claude usage", "err", err)
	}
}
