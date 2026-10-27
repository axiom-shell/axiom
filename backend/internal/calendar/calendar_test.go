package calendar

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// davServer is a fake CalDAV server: one user (u / p) whose principal and
// calendar home are found from /start (a redirect away), holding a
// writable Work calendar and a read-only one with no name
func davServer() http.Handler {
	multistatus := func(w http.ResponseWriter, responses ...string) {
		w.WriteHeader(207)
		fmt.Fprintf(w, `<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/">%s</d:multistatus>`, strings.Join(responses, ""))
	}
	response := func(href, props string) string {
		return `<d:response><d:href>` + href + `</d:href><d:propstat><d:prop>` + props + `</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>` +
			`<d:propstat><d:prop><d:displayname>not this</d:displayname></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>`
	}
	calendar := `<d:resourcetype><d:collection/><c:calendar/></d:resourcetype>`
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if user, pass, ok := r.BasicAuth(); !ok || user != "u" || pass != "p" {
			w.WriteHeader(401)
			return
		}
		switch r.Method + " " + r.URL.Path {
		case "PROPFIND /start":
			http.Redirect(w, r, "/dav/", http.StatusMovedPermanently)
		case "PROPFIND /dav/":
			multistatus(w, response("/dav/", `<d:current-user-principal><d:href>/dav/principals/u/</d:href></d:current-user-principal>`))
		case "PROPFIND /dav/principals/u/":
			multistatus(w, response("/dav/principals/u/", `<c:calendar-home-set><d:href>/dav/cal/u/</d:href></c:calendar-home-set>`))
		case "PROPFIND /dav/cal/u/":
			if r.Header.Get("Depth") != "1" {
				w.WriteHeader(400)
				return
			}
			multistatus(w, response("/dav/cal/u/", `<d:resourcetype><d:collection/></d:resourcetype>`),
				response("/dav/cal/u/work/", calendar+`<d:displayname>Work</d:displayname><a:calendar-color>#FF0000FF</a:calendar-color>`+
					`<c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>`+
					`<d:current-user-privilege-set><d:privilege><d:read/></d:privilege><d:privilege><d:write/></d:privilege></d:current-user-privilege-set>`),
				response("/dav/cal/u/Bank%20holidays/", calendar+
					`<d:current-user-privilege-set><d:privilege><d:read/></d:privilege></d:current-user-privilege-set>`))
		case "PROPFIND /dav/cal/u/work/":
			multistatus(w, response("/dav/cal/u/work/", calendar+`<d:displayname>Work</d:displayname>`))
		default:
			w.WriteHeader(404)
		}
	})
}

func TestDiscoverCalDAV(t *testing.T) {
	t.Parallel()
	ts := httptest.NewServer(davServer())
	t.Cleanup(ts.Close)
	s := New(Options{})
	work := Info{Href: ts.URL + "/dav/cal/u/work/", Name: "Work", Color: "#FF0000", Components: []string{"VEVENT"}}
	cases := []struct {
		name, url string
		want      []Info
	}{
		{"from the server's root, redirected", ts.URL + "/start", []Info{
			{Href: ts.URL + "/dav/cal/u/Bank%20holidays/", Name: "Bank holidays", Components: []string{"VEVENT", "VTODO"}, ReadOnly: true},
			work,
		}},
		{"a calendar's own URL", ts.URL + "/dav/cal/u/work/", []Info{{Href: work.Href, Name: "Work", Components: []string{"VEVENT", "VTODO"}}}},
		// Nothing at the URL: /.well-known/caldav is tried next, and isn't there either
		{"nowhere", ts.URL + "/nothing/", nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			got, err := s.Discover(context.Background(), DiscoverRequest{Kind: "caldav", URL: c.url, Username: "u", Password: "p"})
			if err != nil {
				t.Fatal(err)
			}
			if c.want == nil {
				if got.OK || got.Code != "notFound" {
					t.Errorf("got %+v", got)
				}
				return
			}
			if !got.OK || !reflect.DeepEqual(got.Calendars, c.want) {
				t.Errorf("got %+v\nwant %+v", got, c.want)
			}
		})
	}
}

func TestDiscoverFeed(t *testing.T) {
	t.Parallel()
	feed := "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Team\r\nX-APPLE-CALENDAR-COLOR:#3366CCFF\r\nEND:VCALENDAR\r\n"
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/team.ics":
			fmt.Fprint(w, feed)
		case "/plain.ics":
			fmt.Fprint(w, "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")
		case "/page":
			fmt.Fprint(w, "<html>not a calendar</html>")
		default:
			w.WriteHeader(404)
		}
	}))
	t.Cleanup(ts.Close)
	file := filepath.Join(t.TempDir(), "local.ics")
	if err := os.WriteFile(file, []byte(feed), 0o600); err != nil {
		t.Fatal(err)
	}
	host := strings.TrimPrefix(ts.URL, "http://")
	cases := []struct {
		url, name, color, code string
	}{
		{ts.URL + "/team.ics", "Team", "#3366CC", ""},
		{ts.URL + "/plain.ics", host, "", ""},
		{"file://" + file, "Team", "#3366CC", ""},
		{ts.URL + "/page", "", "", "parse"},
		{ts.URL + "/gone.ics", "", "", "notFound"},
		{"file://" + file + ".missing", "", "", "network"},
	}
	s := New(Options{})
	for _, c := range cases {
		got, err := s.Discover(context.Background(), DiscoverRequest{Kind: "ics", URL: c.url})
		if err != nil {
			t.Fatal(err)
		}
		if c.code != "" {
			if got.OK || got.Code != c.code {
				t.Errorf("%s: %+v, want %s", c.url, got, c.code)
			}
			continue
		}
		want := []Info{{Href: c.url, Name: c.name, Color: c.color, Components: []string{"VEVENT"}, ReadOnly: true}}
		if !got.OK || !reflect.DeepEqual(got.Calendars, want) {
			t.Errorf("%s: %+v", c.url, got)
		}
	}
}

func TestDiscoverFailures(t *testing.T) {
	t.Parallel()
	ts := httptest.NewServer(davServer())
	t.Cleanup(ts.Close)
	s := New(Options{})
	cases := []struct {
		request DiscoverRequest
		code    string
	}{
		{DiscoverRequest{Kind: "caldav", URL: ts.URL + "/start", Username: "u", Password: "wrong"}, "auth"},
		{DiscoverRequest{Kind: "caldav", URL: "https://example.invalid"}, "noPassword"},
		{DiscoverRequest{Kind: "ics", URL: "http://127.0.0.1:9/feed.ics"}, "network"},
		{DiscoverRequest{Kind: "ics", URL: " "}, "notFound"},
		{DiscoverRequest{Kind: "caldav", URL: "https://exa mple.com", Password: "p"}, "network"},
	}
	for _, c := range cases {
		got, err := s.Discover(context.Background(), c.request)
		if err != nil || got.OK || got.Code != c.code {
			t.Errorf("%+v: %+v %v, want %s", c.request, got, err, c.code)
		}
	}
	for in, want := range map[string]string{"webcal://a.b/c.ics": "https://a.b/c.ics", " dav.example.com ": "https://dav.example.com", "http://x": "http://x"} {
		if got := normalizeURL(in); got != want {
			t.Errorf("%q: %q, want %q", in, got, want)
		}
	}
}
