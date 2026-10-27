// Package calendar is the calendars' side effects (CalendarManager):
// finding a CalDAV account's calendars from any URL on its server (the
// principal, its calendar home, the collections there, following
// redirects for every method) and reading an .ics feed's name and color.
// Passwords come in the request from the shell's SecretsManager and are
// never logged or written. Syncing, saving and deleting are still
// scripts/calendar_sync.py's (docs/dev/backend/roadmap.md › Stage 4).
package calendar

import (
	"context"
	"net/http"
	"strings"
	"time"
)

const timeout = 30 * time.Second

// Options are how the service reaches servers; zero values are the real
// ones.
type Options struct {
	Client *http.Client
}

// Service answers the calendar methods.
type Service struct {
	o Options
}

// New makes the service.
func New(o Options) *Service {
	if o.Client == nil {
		o.Client = &http.Client{Timeout: timeout}
	}
	// Redirects are followed by hand, for every method
	client := *o.Client
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	o.Client = &client
	return &Service{o: o}
}

// DiscoverRequest is an account to find the calendars of.
type DiscoverRequest struct {
	Kind     string `json:"kind"` // "caldav" or "ics"
	URL      string `json:"url"`
	Username string `json:"username"`
	Password string `json:"password"`
}

// DiscoverResult is the calendars found, or why none were.
type DiscoverResult struct {
	OK        bool   `json:"ok"`
	Code      string `json:"code,omitempty"`
	Message   string `json:"message,omitempty"`
	Calendars []Info `json:"calendars,omitempty"`
}

// Discover finds an account's calendars ("caldav": from any URL on the
// server), or reads a feed's name and color ("ics").
func (s *Service) Discover(ctx context.Context, r DiscoverRequest) (DiscoverResult, error) {
	calendars, err := s.discover(ctx, r)
	if err != nil {
		return DiscoverResult{}.failed(err)
	}
	return DiscoverResult{OK: true, Calendars: calendars}, nil
}

func (s *Service) discover(ctx context.Context, r DiscoverRequest) ([]Info, error) {
	target := normalizeURL(r.URL)
	if target == "" {
		return nil, fail("notFound", "No address")
	}
	if r.Kind == "ics" {
		return discoverFeed(ctx, s.dav("", ""), target)
	}
	if r.Password == "" {
		return nil, fail("noPassword", "No password saved for this account")
	}
	return discoverCalDAV(ctx, s.dav(r.Username, r.Password), target)
}

func (r DiscoverResult) failed(err error) (DiscoverResult, error) {
	if code := codeOf(err); code != "" {
		return DiscoverResult{Code: code, Message: err.Error()}, nil
	}
	return DiscoverResult{}, err
}

// normalizeURL makes webcal:// https:// and adds a missing scheme
func normalizeURL(u string) string {
	u = strings.TrimSpace(u)
	for _, scheme := range []string{"webcal://", "webcals://"} {
		if rest, ok := strings.CutPrefix(u, scheme); ok {
			u = "https://" + rest
		}
	}
	if u != "" && !strings.Contains(u, "://") {
		u = "https://" + u
	}
	return u
}
