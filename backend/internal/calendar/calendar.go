// Package calendar is the calendars' side effects (CalendarManager):
// CalDAV accounts (discovery from any URL on the server, then getctag and
// calendar-multiget for what changed, PUT and DELETE with If-Match),
// read-only .ics feeds (by ETag) and local calendars (a folder of
// <uid>.ics files under $XDG_DATA_HOME/axiom/calendars/). A sync keeps
// each calendar's raw objects in $XDG_STATE_HOME/axiom/calendar/
// objects.json and writes the shown calendars' occurrences in the range
// to events.json beside it, both mode 600 and atomically, which the shell
// reads (so events show at once, and offline). Parsing, expansion and the
// edits themselves are package ical's. Passwords come in the request from
// the shell's SecretsManager and are never logged or written.
package calendar

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/calendar/ical"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

const (
	timeout       = 30 * time.Second
	multigetBatch = 50
)

// Options are where the calendars live; zero values are the real ones
// (only the two folders must be given).
type Options struct {
	// StateDir holds objects.json and events.json
	StateDir string
	// DataDir holds the local calendars, in calendars/<href>/
	DataDir string
	Log     *slog.Logger
	Client  *http.Client
	Now     func() time.Time
	// Local is the zone floating times and all-day dates are read in;
	// Zone is where new times are written (its TZID; UTC without one)
	Local *time.Location
	Zone  *ical.Zone
}

// Service answers the calendar methods, one at a time (they share the
// state files).
type Service struct {
	o     Options
	mu    sync.Mutex
	zones ical.Zones
}

// New makes the service.
func New(o Options) *Service {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if o.Client == nil {
		o.Client = &http.Client{Timeout: timeout}
	}
	// Redirects are followed by hand, for every method
	client := *o.Client
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	o.Client = &client
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Local == nil {
		o.Local = time.Local
	}
	if o.Zone == nil {
		o.Zone = localZone()
	}
	s := &Service{o: o}
	known := map[string]*time.Location{}
	var mu sync.Mutex
	s.zones = ical.Zones{Local: o.Local, Lookup: func(name string) *time.Location {
		mu.Lock()
		defer mu.Unlock()
		if loc, ok := known[name]; ok {
			return loc
		}
		loc, err := time.LoadLocation(name)
		if err != nil {
			loc = nil
		}
		known[name] = loc
		return loc
	}}
	return s
}

// localZone is the zone named by $TZ or /etc/localtime's link, written
// as UTC when it has no name
func localZone() *ical.Zone {
	name := strings.TrimPrefix(os.Getenv("TZ"), ":")
	if name == "" {
		if target, err := filepath.EvalSymlinks("/etc/localtime"); err == nil {
			if _, after, ok := strings.Cut(target, "zoneinfo/"); ok {
				name = after
			}
		}
	}
	if loc, err := time.LoadLocation(name); err == nil && name != "" && name != "UTC" && name != "Etc/UTC" {
		return &ical.Zone{Loc: loc, Name: name}
	}
	return &ical.Zone{Loc: time.UTC}
}

// DiscoverRequest is an account to find the calendars of.
type DiscoverRequest struct {
	Kind     string `json:"kind"` // "caldav" or "ics"
	URL      string `json:"url"`
	Username string `json:"username"`
	Password string `json:"password"`
}

// DiscoverResult is the calendars found.
type DiscoverResult struct {
	Calendars []Info `json:"calendars"`
}

// Discover finds an account's calendars ("caldav": from any URL on the
// server), or reads a feed's name and color ("ics").
func (s *Service) Discover(ctx context.Context, r DiscoverRequest) (DiscoverResult, error) {
	target := normalizeURL(r.URL)
	var calendars []Info
	var err error
	switch {
	case target == "":
		err = fail(axerr.NotFound, "No address")
	case r.Kind == "ics":
		calendars, err = discoverFeed(ctx, s.dav("", ""), target)
	case r.Password == "":
		err = fail(axerr.Unauthorized, "No password saved for this account")
	default:
		calendars, err = discoverCalDAV(ctx, s.dav(r.Username, r.Password), target)
	}
	return DiscoverResult{Calendars: calendars}, err
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

// Account is an account and the calendars of it to sync (the shown ones).
type Account struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"` // caldav, ics or local
	URL       string `json:"url"`
	Username  string `json:"username"`
	Password  string `json:"password"`
	Calendars []struct {
		Href string `json:"href"`
	} `json:"calendars"`
}

// Range is the span of occurrences kept, in epoch ms.
type Range struct {
	From int64 `json:"from"`
	To   int64 `json:"to"`
}

// SyncRequest is what to sync.
type SyncRequest struct {
	Range    Range     `json:"range"`
	Accounts []Account `json:"accounts"`
}

// SyncError is a calendar that couldn't sync (its last copy kept).
type SyncError struct {
	Calendar string     `json:"calendar"`
	Kind     axerr.Kind `json:"kind"`
	Message  string     `json:"message"`
}

// SyncResult is a sync's outcome; Changed says whether any calendar's
// objects did.
type SyncResult struct {
	Errors  []SyncError `json:"errors"`
	Changed bool        `json:"changed"`
	Count   int         `json:"count"`
}

// object is a calendar object as fetched
type object struct {
	Etag string `json:"etag"`
	ICS  string `json:"ics"`
}

// cached is a calendar's copy: its ctag (a feed's ETag; a local
// calendar's files' etags) and objects by href
type cached struct {
	Ctag    string            `json:"ctag"`
	Objects map[string]object `json:"objects"`
}

// store is objects.json
type store struct {
	Version   int                `json:"version"`
	Calendars map[string]*cached `json:"calendars"`
}

// events is events.json, read by CalendarManager
type events struct {
	Version int               `json:"version"`
	Updated int64             `json:"updated"`
	Range   Range             `json:"range"`
	Events  []ical.Occurrence `json:"events"`
	Errors  []SyncError       `json:"errors"`
}

// Sync fetches what changed in the accounts' calendars, then writes the
// occurrences in the range to events.json.
func (s *Service) Sync(ctx context.Context, r SyncRequest) (SyncResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.sync(ctx, r, "", "")
}

// sync refetches the calendar onlyAccount|onlyCalendar whatever its ctag,
// keeping the others' copies, when one is given
func (s *Service) sync(ctx context.Context, r SyncRequest, onlyAccount, onlyCalendar string) (SyncResult, error) {
	saved := s.load()
	result := SyncResult{Errors: []SyncError{}}
	calendars := map[string]*cached{}
	for _, account := range r.Accounts {
		d := s.dav("", "")
		if account.Kind == "caldav" {
			d = s.dav(account.Username, account.Password)
		}
		for _, cal := range account.Calendars {
			id := account.ID + "|" + cal.Href
			old := saved.Calendars[id]
			force := onlyAccount != ""
			if force && (onlyAccount != account.ID || onlyCalendar != cal.Href) {
				if old != nil {
					calendars[id] = old
				}
				continue
			}
			var fresh *cached
			var err error
			switch {
			case account.Kind == "caldav" && account.Password == "":
				err = fail(axerr.Unauthorized, "No password saved for this account")
			case account.Kind == "caldav":
				fresh, err = syncCalDAV(ctx, d, cal.Href, old, force)
			case account.Kind == "local":
				fresh, err = s.syncLocal(cal.Href, old, force)
			default:
				fresh, err = syncFeed(ctx, d, cal.Href, old, force)
			}
			var failed *axerr.Error
			if errors.As(err, &failed) {
				result.Errors = append(result.Errors, SyncError{Calendar: id, Kind: failed.Kind, Message: err.Error()})
				if old != nil {
					calendars[id] = old
				}
				continue
			} else if err != nil {
				return SyncResult{}, err
			}
			result.Changed = result.Changed || fresh != old
			calendars[id] = fresh
		}
	}
	for id := range calendars {
		result.Changed = result.Changed || saved.Calendars[id] == nil
	}
	result.Changed = result.Changed || len(calendars) != len(saved.Calendars)
	saved.Calendars = calendars
	if err := writeJSON(filepath.Join(s.o.StateDir, "objects.json"), saved); err != nil {
		return SyncResult{}, err
	}
	occurrences := s.expandAll(calendars, r.Range)
	result.Count = len(occurrences)
	err := writeJSON(filepath.Join(s.o.StateDir, "events.json"), events{
		Version: 1, Updated: s.o.Now().UnixMilli(), Range: r.Range, Events: occurrences, Errors: result.Errors,
	})
	if err != nil {
		return SyncResult{}, err
	}
	return result, nil
}

// load is objects.json (empty when it's missing or unreadable)
func (s *Service) load() store {
	saved := store{Version: 1, Calendars: map[string]*cached{}}
	if data, err := os.ReadFile(filepath.Join(s.o.StateDir, "objects.json")); err == nil {
		if json.Unmarshal(data, &saved) != nil || saved.Calendars == nil {
			saved = store{Version: 1, Calendars: map[string]*cached{}}
		}
	}
	return saved
}

func (s *Service) expandAll(calendars map[string]*cached, r Range) []ical.Occurrence {
	out := []ical.Occurrence{}
	for id, cal := range calendars {
		for href, obj := range cal.Objects {
			// One broken object never hides the rest
			parsed, err := ical.Parse(obj.ICS)
			var found []ical.Occurrence
			if err == nil {
				found, err = s.zones.Expand(parsed, id, href, obj.Etag, r.From, r.To)
			}
			if err != nil {
				s.o.Log.Warn("calendar: skipping an object", "href", href, "err", err)
				continue
			}
			out = append(out, found...)
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.Start != b.Start {
			return a.Start < b.Start
		}
		if a.AllDay != b.AllDay {
			return a.AllDay
		}
		return strings.ToLower(a.Title) < strings.ToLower(b.Title)
	})
	return out
}

// syncCalDAV is the calendar's copy: the cached one while its ctag is
// unchanged, else with the objects whose etags changed fetched again
func syncCalDAV(ctx context.Context, d *dav, href string, old *cached, force bool) (*cached, error) {
	found, _, err := d.propfind(ctx, href, []string{"CS:getctag", "D:sync-token"}, "0")
	if err != nil {
		return nil, err
	}
	p := found.first()
	ctag := p.get(nsCS, "getctag").text()
	if ctag == "" {
		ctag = p.get(nsD, "sync-token").text()
	}
	if ctag != "" && old != nil && old.Ctag == ctag && !force {
		return old, nil
	}
	listing, _, err := d.propfind(ctx, href, []string{"D:getetag", "D:resourcetype"}, "1")
	if err != nil {
		return nil, err
	}
	fresh := &cached{Ctag: ctag, Objects: map[string]object{}}
	var wanted []string
	for _, r := range listing {
		if strings.TrimRight(r.href, "/") == strings.TrimRight(href, "/") || r.props.get(nsD, "resourcetype").find(nsD, "collection") != nil {
			continue
		}
		etag := r.props.get(nsD, "getetag").text()
		if kept, ok := old.object(r.href); ok && etag != "" && kept.Etag == etag {
			fresh.Objects[r.href] = kept
		} else {
			wanted = append(wanted, r.href)
		}
	}
	for batch := range slices.Chunk(wanted, multigetBatch) {
		var b strings.Builder
		b.WriteString(`<?xml version="1.0" encoding="utf-8"?><C:calendar-multiget xmlns:D="DAV:" ` +
			`xmlns:C="urn:ietf:params:xml:ns:caldav"><D:prop><D:getetag/><C:calendar-data/></D:prop>`)
		for _, h := range batch {
			b.WriteString("<D:href>" + xmlEscape(pathOf(h)) + "</D:href>")
		}
		b.WriteString("</C:calendar-multiget>")
		got, err := d.report(ctx, href, b.String())
		if err != nil {
			return nil, err
		}
		for _, r := range got {
			if data := r.props.get(nsC, "calendar-data").text(); data != "" {
				fresh.Objects[r.href] = object{Etag: r.props.get(nsD, "getetag").text(), ICS: data}
			}
		}
	}
	return fresh, nil
}

func (c *cached) object(href string) (object, bool) {
	if c == nil {
		return object{}, false
	}
	o, ok := c.Objects[href]
	return o, ok
}

// pathOf is an absolute href's path, as a multiget names it
func pathOf(href string) string {
	if i := strings.Index(href, "://"); i >= 0 {
		rest := href[i+3:]
		href = ""
		if j := strings.IndexByte(rest, '/'); j >= 0 {
			href = rest[j:]
		}
	}
	if i := strings.IndexAny(href, "?#"); i >= 0 {
		href = href[:i]
	}
	return href
}

func xmlEscape(s string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;").Replace(s)
}

// syncFeed checks a feed by its ETag
func syncFeed(ctx context.Context, d *dav, href string, old *cached, force bool) (*cached, error) {
	etag := ""
	if old != nil && !force {
		etag = old.Ctag
	}
	status, newEtag, text, err := fetchFeed(ctx, d, href, etag)
	if err != nil {
		return nil, err
	}
	if status == 304 && old != nil {
		return old, nil
	}
	return &cached{Ctag: newEtag, Objects: map[string]object{href: {Etag: newEtag, ICS: text}}}, nil
}

// localDir is a local calendar's folder, its href one plain name
func (s *Service) localDir(href string) (string, error) {
	if s.o.DataDir == "" || href == "" || href == "." || href == ".." || strings.ContainsAny(href, `/\`) {
		return "", fail(axerr.NotFound, "Not a local calendar: %q", href)
	}
	return filepath.Join(s.o.DataDir, "calendars", href), nil
}

// localPath is the file of a local event href (<calendar>/<uid>.ics)
func (s *Service) localPath(href string) (string, error) {
	calendar, name, _ := strings.Cut(href, "/")
	if !strings.HasSuffix(name, ".ics") || strings.Contains(name, "/") || strings.HasPrefix(name, ".") {
		return "", fail(axerr.NotFound, "Not a local event: %q", href)
	}
	dir, err := s.localDir(calendar)
	return filepath.Join(dir, name), err
}

// localEtag is a file's mtime and size ("" when it's missing)
func localEtag(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		return ""
	}
	return strconv.FormatInt(info.ModTime().UnixNano(), 10) + "-" + strconv.FormatInt(info.Size(), 10)
}

// syncLocal rereads only the files whose etag changed
func (s *Service) syncLocal(href string, old *cached, force bool) (*cached, error) {
	folder, err := s.localDir(href)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(folder)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	fresh := &cached{Objects: map[string]object{}}
	var keys []string
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".ics") || strings.HasPrefix(name, ".") {
			continue
		}
		key, path := href+"/"+name, filepath.Join(folder, name)
		etag := localEtag(path)
		if kept, ok := old.object(key); ok && !force && etag != "" && kept.Etag == etag {
			fresh.Objects[key] = kept
		} else if data, err := os.ReadFile(path); err == nil && etag != "" {
			fresh.Objects[key] = object{Etag: etag, ICS: string(data)}
		} else {
			continue
		}
		keys = append(keys, key)
	}
	sort.Strings(keys)
	tags := make([]string, len(keys))
	for i, key := range keys {
		tags[i] = key + ":" + fresh.Objects[key].Etag
	}
	fresh.Ctag = strings.Join(tags, "|")
	if old != nil && old.Ctag == fresh.Ctag && !force {
		return old, nil
	}
	return fresh, nil
}

// EditRequest names the event a save or delete is for, with what a sync
// needs (the calendar is synced again after).
type EditRequest struct {
	Range    Range     `json:"range"`
	Accounts []Account `json:"accounts"`
	Account  string    `json:"account"`
	Calendar string    `json:"calendar"` // its href
	Href     string    `json:"href"`     // the event's ("" for a new one)
	Etag     string    `json:"etag"`
	// "series" (the whole event) or "occurrence" (the one at Rid)
	Scope string `json:"scope"`
	Rid   string `json:"rid"`
}

// SaveRequest is an event to save.
type SaveRequest struct {
	EditRequest
	Event ical.Event `json:"event"`
}

// EditResult is the event's href and what the sync after found.
type EditResult struct {
	Href   string      `json:"href"`
	Errors []SyncError `json:"errors"`
}

// writer is where an edit goes: a CalDAV account's server, or a local
// calendar's folder (d nil)
type writer struct {
	d *dav
}

func (s *Service) writer(r EditRequest) (writer, error) {
	i := slices.IndexFunc(r.Accounts, func(a Account) bool { return a.ID == r.Account })
	if i < 0 {
		return writer{}, fail(axerr.NotFound, "Unknown account")
	}
	switch account := r.Accounts[i]; {
	case account.Kind == "local":
		return writer{}, nil
	case account.Kind != "caldav":
		return writer{}, fail(axerr.Refused, "Subscriptions are read-only")
	case account.Password == "":
		return writer{}, fail(axerr.Unauthorized, "No password saved for this account")
	default:
		return writer{d: s.dav(account.Username, account.Password)}, nil
	}
}

// cachedObject is the event as last synced
func (s *Service) cachedObject(r EditRequest) (object, *ical.Component, error) {
	obj, ok := s.load().Calendars[r.Account+"|"+r.Calendar].object(r.Href)
	if !ok {
		return object{}, nil, fail(axerr.Conflict, "The event changed on the server")
	}
	cal, err := ical.Parse(obj.ICS)
	if err != nil {
		return object{}, nil, fail(axerr.BadReply, "The event isn't iCalendar: %v", err)
	}
	return obj, cal, nil
}

// resync syncs the edited calendar again
func (s *Service) resync(ctx context.Context, r EditRequest, href string) (EditResult, error) {
	synced, err := s.sync(ctx, SyncRequest{Range: r.Range, Accounts: r.Accounts}, r.Account, r.Calendar)
	return EditResult{Href: href, Errors: synced.Errors}, err
}

// Save writes an event: a new one (no Href) in the local zone, else the
// stored object edited in place (unknown properties kept) for the whole
// series or one occurrence; then syncs its calendar again.
func (s *Service) Save(ctx context.Context, r SaveRequest) (EditResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	w, err := s.writer(r.EditRequest)
	if err != nil {
		return EditResult{}, err
	}
	tz, now := *s.o.Zone, s.o.Now()
	if r.Href == "" {
		uid := newUID()
		href := strings.TrimRight(r.Calendar, "/") + "/" + uid + ".ics"
		if err := s.put(ctx, w, href, s.zones.NewEvent(r.Event, tz, uid, now), ""); err != nil {
			return EditResult{}, err
		}
		return s.resync(ctx, r.EditRequest, href)
	}
	obj, cal, err := s.cachedObject(r.EditRequest)
	if err != nil {
		return EditResult{}, err
	}
	if r.Scope == "occurrence" && r.Rid != "" {
		err = s.zones.ApplyOccurrence(cal, r.Event, r.Rid, tz, now)
	} else {
		err = s.zones.ApplySeries(cal, r.Event, tz, now)
	}
	if err != nil {
		return EditResult{}, fail(axerr.BadReply, "%v", err)
	}
	if err := s.put(ctx, w, r.Href, cal, firstOf(r.Etag, obj.Etag)); err != nil {
		return EditResult{}, err
	}
	return s.resync(ctx, r.EditRequest, r.Href)
}

// Delete removes an event, or with scope "occurrence" excludes the one at
// Rid (an EXDATE); then syncs its calendar again.
func (s *Service) Delete(ctx context.Context, r EditRequest) (EditResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	w, err := s.writer(r)
	if err != nil {
		return EditResult{}, err
	}
	if r.Scope == "occurrence" && r.Rid != "" {
		obj, cal, err := s.cachedObject(r)
		if err != nil {
			return EditResult{}, err
		}
		if s.zones.ExcludeOccurrence(cal, r.Rid, *s.o.Zone, s.o.Now()) {
			if err := s.put(ctx, w, r.Href, cal, firstOf(r.Etag, obj.Etag)); err != nil {
				return EditResult{}, err
			}
			return s.resync(ctx, r, r.Href)
		}
	}
	if w.d == nil {
		path, err := s.localPath(r.Href)
		if err != nil {
			return EditResult{}, err
		}
		etag := localEtag(path)
		if etag != "" && r.Etag != "" && etag != r.Etag {
			return EditResult{}, fail(axerr.Conflict, "The event changed on disk")
		}
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return EditResult{}, err
		}
		return s.resync(ctx, r, r.Href)
	}
	headers := map[string]string{}
	if r.Etag != "" {
		headers["If-Match"] = r.Etag
	}
	resp, err := w.d.request(ctx, "DELETE", r.Href, nil, headers, "")
	if err != nil {
		return EditResult{}, err
	}
	if resp.status != 404 {
		if err := checkWrite(resp, "DELETE"); err != nil {
			return EditResult{}, err
		}
	}
	return s.resync(ctx, r, r.Href)
}

// newUID is a random (version 4) UUID
func newUID() string {
	b := make([]byte, 16)
	rand.Read(b)
	b[6], b[8] = b[6]&0x0f|0x40, b[8]&0x3f|0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func firstOf(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// put writes an event: PUT with If-Match (If-None-Match: * when new), or
// a local calendar's file atomically, its etag checked
func (s *Service) put(ctx context.Context, w writer, href string, cal *ical.Component, etag string) error {
	s.zones.AddMissingTimezones(cal)
	data := []byte(cal.Encode())
	if w.d == nil {
		path, err := s.localPath(href)
		if err != nil {
			return err
		}
		if current := localEtag(path); current != etag {
			return fail(axerr.Conflict, "The event changed on disk")
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			return err
		}
		return fsx.WriteFile(path, data, 0o600)
	}
	headers := map[string]string{"Content-Type": "text/calendar; charset=utf-8", "If-None-Match": "*"}
	if etag != "" {
		headers = map[string]string{"Content-Type": "text/calendar; charset=utf-8", "If-Match": etag}
	}
	resp, err := w.d.request(ctx, "PUT", href, data, headers, "")
	if err != nil {
		return err
	}
	return checkWrite(resp, "PUT")
}

func checkWrite(resp response, method string) error {
	switch {
	case resp.status == 412:
		return fail(axerr.Conflict, "The event changed on the server")
	case resp.status == 403:
		return fail(axerr.Refused, "The server doesn't allow changes to this calendar")
	case resp.status >= 400:
		return fail(axerr.Internal, "%s: HTTP %d %s", method, resp.status, strings.ToValidUTF8(string(resp.body[:min(len(resp.body), 200)]), "�"))
	}
	return nil
}

// writeJSON writes atomically, mode 600 (events are private)
func writeJSON(path string, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return axerr.Wrap(axerr.Internal, fsx.WriteFile(path, data, 0o600), "writing %s", path)
}
