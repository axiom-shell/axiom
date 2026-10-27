package calendar

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/calendar/ical"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
)

const event = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:%s\r\nDTSTART:20260709T140000Z\r\nDTEND:20260709T150000Z\r\nSUMMARY:%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const series = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:gym\r\nDTSTART:20260706T180000Z\r\nDTEND:20260706T190000Z\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:Gym\r\nX-KEPT:yes\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

var july = Range{From: time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC).UnixMilli(), To: time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC).UnixMilli()}

func ms(d, h int) int64 { return time.Date(2026, 7, d, h, 0, 0, 0, time.UTC).UnixMilli() }

// calServer is a fake CalDAV calendar at /cal/ (user u / p): objects by name
// with numbered etags, PUT and DELETE honouring If-Match and
// If-None-Match
type calServer struct {
	mu        sync.Mutex
	objects   map[string]string
	etags     map[string]int
	version   int
	multigets int
	requested []string
}

func newCalServer(objects map[string]string) *calServer {
	s := &calServer{objects: map[string]string{}, etags: map[string]int{}}
	for name, ics := range objects {
		s.version++
		s.objects[name], s.etags[name] = ics, s.version
	}
	return s
}

func (s *calServer) etag(name string) string { return `"` + strconv.Itoa(s.etags[name]) + `"` }

func (s *calServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if user, pass, ok := r.BasicAuth(); !ok || user != "u" || pass != "p" {
		w.WriteHeader(401)
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	body, _ := io.ReadAll(r.Body)
	multistatus := func(responses ...string) {
		w.WriteHeader(207)
		fmt.Fprintf(w, `<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">%s</d:multistatus>`, strings.Join(responses, ""))
	}
	response := func(href, props string) string {
		return `<d:response><d:href>` + href + `</d:href><d:propstat><d:prop>` + props + `</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>`
	}
	name := strings.TrimPrefix(r.URL.Path, "/cal/")
	switch r.Method {
	case "PROPFIND":
		if r.Header.Get("Depth") == "0" {
			multistatus(response("/cal/", `<cs:getctag>`+strconv.Itoa(s.version)+`</cs:getctag>`))
			return
		}
		responses := []string{response("/cal/", `<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>`)}
		for name := range s.objects {
			responses = append(responses, response("/cal/"+name, `<d:getetag>`+s.etag(name)+`</d:getetag>`))
		}
		multistatus(responses...)
	case "REPORT":
		s.multigets++
		var responses []string
		for _, m := range regexp.MustCompile(`<D:href>/cal/([^<]*)</D:href>`).FindAllStringSubmatch(string(body), -1) {
			s.requested = append(s.requested, m[1])
			data := strings.NewReplacer("&", "&amp;", "<", "&lt;").Replace(s.objects[m[1]])
			responses = append(responses, response("/cal/"+m[1], `<d:getetag>`+s.etag(m[1])+`</d:getetag><c:calendar-data>`+data+`</c:calendar-data>`))
		}
		multistatus(responses...)
	case "PUT", "DELETE":
		_, exists := s.objects[name]
		if match := r.Header.Get("If-Match"); (match != "" && (!exists || match != s.etag(name))) || (r.Header.Get("If-None-Match") == "*" && exists) {
			w.WriteHeader(412)
			return
		}
		if name == "readonly.ics" {
			w.WriteHeader(403)
			return
		}
		s.version++
		if r.Method == "DELETE" {
			delete(s.objects, name)
		} else {
			s.objects[name], s.etags[name] = string(body), s.version
		}
		w.WriteHeader(204)
	}
}

func newService(t *testing.T) *Service {
	t.Helper()
	dir := t.TempDir()
	return New(Options{StateDir: filepath.Join(dir, "state"), DataDir: filepath.Join(dir, "data"), Secrets: testSecrets(t), Local: time.UTC, Zone: &ical.Zone{Loc: time.UTC}})
}

// testSecrets holds the CalDAV passwords "p" (account acc) and "wrong"
// (account wrong) in its own secrets.json, with no keyring
func testSecrets(t *testing.T) *secrets.Store {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "secrets.json"), []byte(`{"calendar:acc": "p", "calendar:wrong": "wrong"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	return secrets.New(secrets.Options{StateDir: dir, SecretTool: filepath.Join(dir, "no-secret-tool")})
}

func readEvents(t *testing.T, s *Service) events {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(s.o.StateDir, "events.json"))
	if err != nil {
		t.Fatal(err)
	}
	var e events
	if err := json.Unmarshal(data, &e); err != nil {
		t.Fatal(err)
	}
	return e
}

func titles(t *testing.T, s *Service) []string {
	t.Helper()
	var out []string
	for _, e := range readEvents(t, s).Events {
		out = append(out, e.Title)
	}
	return out
}

func account(id, kind string, hrefs ...string) Account {
	a := Account{ID: id, Kind: kind}
	if kind == "caldav" {
		a.Username = "u"
	}
	for _, h := range hrefs {
		a.Calendars = append(a.Calendars, struct {
			Href string `json:"href"`
		}{h})
	}
	return a
}

func TestCalDAVSync(t *testing.T) {
	t.Parallel()
	fake := newCalServer(map[string]string{"a.ics": fmt.Sprintf(event, "a", "Dentist"), "b.ics": fmt.Sprintf(event, "b", "Lunch")})
	ts := httptest.NewServer(fake)
	t.Cleanup(ts.Close)
	s := newService(t)
	ctx := context.Background()
	cal := ts.URL + "/cal/"
	accounts := []Account{account("acc", "caldav", cal)}
	sync := func() SyncResult {
		t.Helper()
		r, err := s.Sync(ctx, SyncRequest{Range: july, Accounts: accounts})
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	if r := sync(); !r.Changed || r.Count != 2 || len(r.Errors) != 0 {
		t.Errorf("first sync %+v", r)
	}
	e := readEvents(t, s).Events
	if !reflect.DeepEqual(titles(t, s), []string{"Dentist", "Lunch"}) || e[0].Calendar != "acc|"+cal || e[0].Href != cal+"a.ics" {
		t.Errorf("events %+v", e)
	}
	info, _ := os.Stat(filepath.Join(s.o.StateDir, "events.json"))
	if info.Mode().Perm() != 0o600 {
		t.Errorf("events.json mode %v", info.Mode().Perm())
	}
	// An unchanged ctag isn't fetched again
	if r := sync(); r.Changed || fake.multigets != 1 {
		t.Errorf("unchanged sync %+v, %d multigets", r, fake.multigets)
	}
	// A new ctag fetches only the objects whose etag changed
	fake.mu.Lock()
	fake.version++
	fake.objects["b.ics"], fake.etags["b.ics"], fake.requested = fmt.Sprintf(event, "b", "Dinner"), fake.version, nil
	fake.mu.Unlock()
	if r := sync(); !r.Changed || !reflect.DeepEqual(fake.requested, []string{"b.ics"}) {
		t.Errorf("changed sync %+v, fetched %v", r, fake.requested)
	}
	// No password: the calendar reports it and keeps its copy
	if err := s.o.Secrets.Clear(ctx, "calendar", "acc"); err != nil {
		t.Fatal(err)
	}
	if r := sync(); len(r.Errors) != 1 || r.Errors[0].Kind != axerr.Unauthorized || r.Count != 2 {
		t.Errorf("no password %+v", r)
	}
}

func TestCalDAVEdits(t *testing.T) {
	t.Parallel()
	fake := newCalServer(map[string]string{"gym.ics": series, "readonly.ics": fmt.Sprintf(event, "r", "Fixed")})
	ts := httptest.NewServer(fake)
	t.Cleanup(ts.Close)
	s := newService(t)
	ctx := context.Background()
	cal := ts.URL + "/cal/"
	edit := EditRequest{Range: july, Accounts: []Account{account("acc", "caldav", cal)}, Account: "acc", Calendar: cal, Scope: "series"}
	if _, err := s.Sync(ctx, SyncRequest{Range: july, Accounts: edit.Accounts}); err != nil {
		t.Fatal(err)
	}
	gymEtag := fake.etag("gym.ics")

	// A new event: If-None-Match, a UID of its own, read back by the sync after
	created, err := s.Save(ctx, SaveRequest{EditRequest: edit, Event: ical.Event{Title: "Dentist", Start: ms(9, 14), End: ms(9, 15), Repeat: "none"}})
	if err != nil || !regexp.MustCompile(`/cal/[0-9a-f-]{36}\.ics$`).MatchString(created.Href) {
		t.Fatalf("created %+v %v", created, err)
	}
	if got := titles(t, s); !slices.Contains(got, "Dentist") {
		t.Errorf("after create %v", got)
	}

	// One occurrence moved: an override in the stored object, its other
	// properties kept
	one := edit
	one.Href, one.Etag, one.Scope, one.Rid = cal+"gym.ics", gymEtag, "occurrence", fmt.Sprintf("T:%d", ms(13, 18)/1000)
	if _, err := s.Save(ctx, SaveRequest{EditRequest: one, Event: ical.Event{Title: "Gym (late)", Start: ms(13, 20), End: ms(13, 21)}}); err != nil {
		t.Fatal(err)
	}
	if stored := fake.objects["gym.ics"]; !strings.Contains(stored, "RECURRENCE-ID:20260713T180000Z") || strings.Count(stored, "X-KEPT:yes") != 2 {
		t.Errorf("stored:\n%s", stored)
	}
	// A stale etag is a conflict, not an overwrite
	if _, err := s.Save(ctx, SaveRequest{EditRequest: one, Event: ical.Event{Title: "Again", Start: ms(13, 20), End: ms(13, 21)}}); axerr.KindOf(err) != axerr.Conflict {
		t.Errorf("stale save: %v", err)
	}
	// An occurrence deleted (an EXDATE), then the whole series
	one.Etag, one.Rid = fake.etag("gym.ics"), fmt.Sprintf("T:%d", ms(20, 18)/1000)
	if _, err := s.Delete(ctx, one); err != nil || !strings.Contains(fake.objects["gym.ics"], "EXDATE:20260720T180000Z") {
		t.Fatalf("exclude: %v\n%s", err, fake.objects["gym.ics"])
	}
	all := edit
	all.Href, all.Etag = cal+"gym.ics", fake.etag("gym.ics")
	if _, err := s.Delete(ctx, all); err != nil || fake.objects["gym.ics"] != "" {
		t.Fatalf("delete: %v", err)
	}
	if got := titles(t, s); slices.Contains(got, "Gym") || slices.Contains(got, "Gym (late)") {
		t.Errorf("after delete %v", got)
	}
	// What the server refuses
	fixed := edit
	fixed.Href = cal + "readonly.ics"
	if _, err := s.Save(ctx, SaveRequest{EditRequest: fixed, Event: ical.Event{Title: "No"}}); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("read-only: %v", err)
	}
	unknown := edit
	unknown.Account = "nope"
	if _, err := s.Save(ctx, SaveRequest{EditRequest: unknown}); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("unknown account: %v", err)
	}
	feed := edit
	feed.Accounts = []Account{account("acc", "ics", cal)}
	if _, err := s.Delete(ctx, feed); axerr.KindOf(err) != axerr.Refused {
		t.Errorf("feed: %v", err)
	}
}

func TestFeedSync(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	gone := false
	feedText := "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:trip\r\nDTSTART;VALUE=DATE:20260710\r\nDTEND;VALUE=DATE:20260713\r\nSUMMARY:Trip\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case gone:
			w.WriteHeader(404)
		case r.Header.Get("If-None-Match") == `"v1"`:
			w.WriteHeader(304)
		default:
			w.Header().Set("ETag", `"v1"`)
			io.WriteString(w, feedText)
		}
	}))
	t.Cleanup(ts.Close)
	s := newService(t)
	ctx := context.Background()
	url := ts.URL + "/team.ics"
	accounts := []Account{account("feed", "ics", url)}
	r, err := s.Sync(ctx, SyncRequest{Range: july, Accounts: accounts})
	if err != nil || !r.Changed || r.Count != 1 {
		t.Fatalf("sync %+v %v", r, err)
	}
	trip := readEvents(t, s).Events[0]
	if trip.Title != "Trip" || !trip.AllDay || trip.DayStart != "2026-07-10" || trip.DayEnd != "2026-07-13" || trip.Calendar != "feed|"+url {
		t.Errorf("trip %+v", trip)
	}
	// Unchanged (304), then gone: the last copy is kept and the error reported
	if r, _ := s.Sync(ctx, SyncRequest{Range: july, Accounts: accounts}); r.Changed {
		t.Errorf("304 sync %+v", r)
	}
	mu.Lock()
	gone = true
	mu.Unlock()
	r, _ = s.Sync(ctx, SyncRequest{Range: july, Accounts: accounts})
	if len(r.Errors) != 1 || r.Errors[0].Kind != axerr.NotFound || len(readEvents(t, s).Events) != 1 || len(readEvents(t, s).Errors) != 1 {
		t.Errorf("gone sync %+v", r)
	}
	// A dropped calendar is a change
	if r, _ := s.Sync(ctx, SyncRequest{Range: july}); !r.Changed || r.Count != 0 {
		t.Errorf("no calendars %+v", r)
	}
}

// A local calendar: an event saved as a file in its folder, edited, read
// back by sync and deleted; hrefs outside <dataDir>/calendars are refused
func TestLocalCalendar(t *testing.T) {
	t.Parallel()
	s := newService(t)
	ctx := context.Background()
	folder := filepath.Join(s.o.DataDir, "calendars", "personal")
	edit := EditRequest{Range: july, Accounts: []Account{account("here", "local", "personal")}, Account: "here", Calendar: "personal", Scope: "series"}
	dentist := ical.Event{Title: "Dentist", Start: ms(9, 14), End: ms(9, 15)}
	saved, err := s.Save(ctx, SaveRequest{EditRequest: edit, Event: dentist})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(s.o.DataDir, "calendars", saved.Href)
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("saved %+v: %v", saved, err)
	}
	e := readEvents(t, s).Events
	if len(e) != 1 || e[0].Title != "Dentist" || e[0].Calendar != "here|personal" || e[0].Href != saved.Href {
		t.Fatalf("events %+v", e)
	}
	changed := edit
	changed.Href, changed.Etag = saved.Href, e[0].Etag
	moved := dentist
	moved.Title = "Dentist (moved)"
	if _, err := s.Save(ctx, SaveRequest{EditRequest: changed, Event: moved}); err != nil || !reflect.DeepEqual(titles(t, s), []string{"Dentist (moved)"}) {
		t.Fatalf("edit: %v %v", err, titles(t, s))
	}
	stale := changed
	stale.Etag = "0-0"
	if _, err := s.Save(ctx, SaveRequest{EditRequest: stale, Event: dentist}); axerr.KindOf(err) != axerr.Conflict {
		t.Errorf("stale: %v", err)
	}
	// A file dropped into the folder by hand is picked up; one half written isn't
	os.WriteFile(filepath.Join(folder, "extra.ics"), fmt.Appendf(nil, event, "x", "Extra"), 0o600)
	os.WriteFile(filepath.Join(folder, ".tmp-y.ics"), fmt.Appendf(nil, event, "y", "Half written"), 0o600)
	if r, _ := s.Sync(ctx, SyncRequest{Range: july, Accounts: edit.Accounts}); !r.Changed || r.Count != 2 {
		t.Errorf("dropped in %+v", r)
	}
	if r, _ := s.Sync(ctx, SyncRequest{Range: july, Accounts: edit.Accounts}); r.Changed {
		t.Errorf("unchanged %+v", r)
	}
	os.Remove(filepath.Join(folder, "extra.ics"))
	gone := changed
	gone.Etag = readEvents(t, s).Events[0].Etag
	if _, err := s.Delete(ctx, gone); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) || len(readEvents(t, s).Events) != 0 {
		t.Errorf("deleted: %v %v", err, readEvents(t, s).Events)
	}
	for _, bad := range []string{"..", "a/b", ""} {
		r, _ := s.Sync(ctx, SyncRequest{Range: july, Accounts: []Account{account("here", "local", bad)}})
		if len(r.Errors) != 1 || r.Errors[0].Kind != axerr.NotFound {
			t.Errorf("%q: %+v", bad, r)
		}
	}
	escape := edit
	escape.Href = "personal/../../escape.ics"
	if _, err := s.Delete(ctx, escape); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("escape: %v", err)
	}
}
