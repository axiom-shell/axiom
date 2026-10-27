package calendar

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/calendar/ical"
)

// The WebDAV namespaces
const (
	nsD = "DAV:"
	nsC = "urn:ietf:params:xml:ns:caldav"
	nsA = "http://apple.com/ns/ical/"
)

const maxBody = 64 << 20

// calProps are what a calendar collection says of itself
var calProps = []string{"D:resourcetype", "D:displayname", "A:calendar-color", "C:supported-calendar-component-set",
	"CS:getctag", "D:sync-token", "D:current-user-privilege-set"}

// dav is one account's connection: its client and Basic credentials
type dav struct {
	client *http.Client
	auth   string
}

func (s *Service) dav(username, password string) *dav {
	d := &dav{client: s.o.Client}
	if username != "" || password != "" {
		d.auth = "Basic " + base64.StdEncoding.EncodeToString([]byte(username+":"+password))
	}
	return d
}

// response is a request's status, body and final URL
type response struct {
	status int
	body   []byte
	url    string
}

// request follows redirects for any method (iCloud moves an account to a
// pNN-caldav host), and reads a file:// feed from disk
func (d *dav) request(ctx context.Context, method, target string, body []byte, headers map[string]string, depth string) (response, error) {
	for range 6 {
		u, err := url.Parse(target)
		if err != nil {
			return response{}, fail("network", "Could not reach %s: %v", target, err)
		}
		if u.Scheme == "file" {
			data, err := os.ReadFile(u.Path)
			if err != nil {
				return response{}, fail("network", "Could not reach %s: %v", u.Host, err)
			}
			return response{status: 200, body: data, url: target}, nil
		}
		var reader io.Reader
		if body != nil {
			reader = bytes.NewReader(body)
		}
		req, err := http.NewRequestWithContext(ctx, method, target, reader)
		if err != nil {
			return response{}, fail("network", "Could not reach %s: %v", u.Host, err)
		}
		req.Header.Set("User-Agent", "axiom-calendar")
		if d.auth != "" {
			req.Header.Set("Authorization", d.auth)
		}
		if depth != "" {
			req.Header.Set("Depth", depth)
		}
		if body != nil {
			req.Header.Set("Content-Type", "application/xml; charset=utf-8")
		}
		for key, value := range headers {
			req.Header.Set(key, value)
		}
		resp, err := d.client.Do(req)
		if err != nil {
			return response{}, fail("network", "Could not reach %s: %v", u.Host, err)
		}
		data, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
		resp.Body.Close()
		if err != nil {
			return response{}, fail("network", "Could not reach %s: %v", u.Host, err)
		}
		switch location := resp.Header.Get("Location"); {
		case location != "" && slices.Contains([]int{301, 302, 303, 307, 308}, resp.StatusCode):
			next, err := u.Parse(location)
			if err != nil {
				return response{}, fail("network", "Could not reach %s: %v", location, err)
			}
			target = next.String()
			continue
		case resp.StatusCode == 401:
			return response{}, fail("auth", "The server refused the username or password")
		}
		return response{status: resp.StatusCode, body: data, url: target}, nil
	}
	return response{}, fail("network", "Too many redirects")
}

func (d *dav) propfind(ctx context.Context, target string, props []string, depth string) (multistatus, string, error) {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" ` +
		`xmlns:CS="http://calendarserver.org/ns/" xmlns:A="http://apple.com/ns/ical/"><D:prop>`)
	for _, p := range props {
		b.WriteString("<" + p + "/>")
	}
	b.WriteString("</D:prop></D:propfind>")
	resp, err := d.request(ctx, "PROPFIND", target, []byte(b.String()), nil, depth)
	if err != nil {
		return nil, "", err
	}
	if resp.status == 404 {
		return nil, "", fail("notFound", "Nothing at %s", target)
	}
	if resp.status >= 400 {
		return nil, "", fail("server", "PROPFIND %s: HTTP %d", target, resp.status)
	}
	found, err := parseMultistatus(resp.body, resp.url)
	return found, resp.url, err
}

// node is an XML element, kept whole
type node struct {
	XMLName xml.Name
	Attrs   []xml.Attr `xml:",any,attr"`
	Text    string     `xml:",chardata"`
	Nodes   []node     `xml:",any"`
}

func (n *node) find(space, local string) *node {
	if n == nil {
		return nil
	}
	for i := range n.Nodes {
		if n.Nodes[i].XMLName.Space == space && n.Nodes[i].XMLName.Local == local {
			return &n.Nodes[i]
		}
	}
	return nil
}

func (n *node) text() string {
	if n == nil {
		return ""
	}
	return strings.TrimSpace(n.Text)
}

// href is an element's D:href ("" without one)
func (n *node) href() string { return n.find(nsD, "href").text() }

// props are one resource's properties, by name
type props map[xml.Name]*node

func (p props) get(space, local string) *node { return p[xml.Name{Space: space, Local: local}] }

// resource is a multistatus response's absolute href and its properties
type resource struct {
	href  string
	props props
}

type multistatus []resource

func (m multistatus) first() props {
	if len(m) == 0 {
		return props{}
	}
	return m[0].props
}

// parseMultistatus reads a 207's responses, keeping only 200 propstats
func parseMultistatus(data []byte, base string) (multistatus, error) {
	var root node
	decoder := xml.NewDecoder(bytes.NewReader(data))
	decoder.CharsetReader = func(_ string, input io.Reader) (io.Reader, error) { return input, nil }
	if err := decoder.Decode(&root); err != nil {
		return nil, fail("parse", "The server's reply isn't XML: %v", err)
	}
	baseURL, _ := url.Parse(base)
	var out multistatus
	index := map[string]int{}
	for _, r := range root.Nodes {
		if r.XMLName != (xml.Name{Space: nsD, Local: "response"}) || r.href() == "" {
			continue
		}
		ref, err := url.Parse(r.href())
		if err != nil {
			continue
		}
		href := baseURL.ResolveReference(ref).String()
		i, ok := index[href]
		if !ok {
			i = len(out)
			index[href] = i
			out = append(out, resource{href: href, props: props{}})
		}
		for _, ps := range r.Nodes {
			if ps.XMLName != (xml.Name{Space: nsD, Local: "propstat"}) {
				continue
			}
			if status := ps.find(nsD, "status").text(); status != "" && !strings.Contains(status+" ", " 200 ") {
				continue
			}
			if prop := ps.find(nsD, "prop"); prop != nil {
				for j := range prop.Nodes {
					out[i].props[prop.Nodes[j].XMLName] = &prop.Nodes[j]
				}
			}
		}
	}
	return out, nil
}

func isCalendar(p props) bool { return p.get(nsD, "resourcetype").find(nsC, "calendar") != nil }

// Info is what a server says of a calendar.
type Info struct {
	Href       string   `json:"href"`
	Name       string   `json:"name"`
	Color      string   `json:"color"`
	Components []string `json:"components"`
	ReadOnly   bool     `json:"readOnly"`
}

func calendarInfo(href string, p props) Info {
	components := []string{"VEVENT", "VTODO"}
	if set := p.get(nsC, "supported-calendar-component-set"); set != nil {
		components = []string{}
		for _, comp := range set.Nodes {
			if comp.XMLName == (xml.Name{Space: nsC, Local: "comp"}) {
				for _, a := range comp.Attrs {
					if a.Name.Local == "name" {
						components = append(components, a.Value)
					}
				}
			}
		}
	}
	readOnly := false
	if privileges := p.get(nsD, "current-user-privilege-set"); privileges != nil {
		readOnly = true
		for _, privilege := range privileges.Nodes {
			for _, child := range privilege.Nodes {
				if child.XMLName.Space == nsD && slices.Contains([]string{"write", "write-content", "all", "bind"}, child.XMLName.Local) {
					readOnly = false
				}
			}
		}
	}
	color := p.get(nsA, "calendar-color").text()
	if len(color) == 9 && color[0] == '#' {
		color = color[:7]
	}
	name := p.get(nsD, "displayname").text()
	if name == "" {
		path := strings.TrimRight(href, "/")
		name, _ = url.PathUnescape(path[strings.LastIndex(path, "/")+1:])
	}
	return Info{Href: href, Name: name, Color: color, Components: components, ReadOnly: readOnly}
}

// discoverCalDAV finds an account's calendars from any URL on its server:
// the principal, its calendar home, the collections there; then the same
// from /.well-known/caldav
func discoverCalDAV(ctx context.Context, d *dav, start string) ([]Info, error) {
	base, _ := url.Parse(start)
	wellKnown, _ := base.Parse("/.well-known/caldav")
	var last error
	for _, candidate := range []string{start, wellKnown.String()} {
		found, final, err := d.propfind(ctx, candidate, append([]string{"D:current-user-principal", "D:resourcetype", "C:calendar-home-set"}, calProps...), "0")
		if err != nil {
			if codeOf(err) == "auth" {
				return nil, err
			}
			last = err
			continue
		}
		p := found.first()
		if isCalendar(p) {
			return []Info{calendarInfo(final, p)}, nil
		}
		home, principal := p.get(nsC, "calendar-home-set").href(), p.get(nsD, "current-user-principal").href()
		if home == "" && principal != "" {
			found, pfinal, err := d.propfind(ctx, resolve(final, principal), []string{"C:calendar-home-set"}, "0")
			if err != nil {
				return nil, err
			}
			if home = found.first().get(nsC, "calendar-home-set").href(); home != "" {
				home = resolve(pfinal, home)
			}
		} else if home != "" {
			home = resolve(final, home)
		}
		if home == "" {
			home = final
		}
		listing, _, err := d.propfind(ctx, home, calProps, "1")
		if err != nil {
			return nil, err
		}
		var calendars []Info
		for _, r := range listing {
			if isCalendar(r.props) {
				calendars = append(calendars, calendarInfo(r.href, r.props))
			}
		}
		if len(calendars) > 0 {
			slices.SortStableFunc(calendars, func(a, b Info) int { return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name)) })
			return calendars, nil
		}
		last = fail("notCalendar", "No calendars found at that address")
	}
	return nil, last
}

func resolve(base, ref string) string {
	b, err := url.Parse(base)
	if err != nil {
		return ref
	}
	r, err := b.Parse(ref)
	if err != nil {
		return ref
	}
	return r.String()
}

// fetchFeed GETs an .ics feed's text
func fetchFeed(ctx context.Context, d *dav, target string) (string, error) {
	resp, err := d.request(ctx, "GET", target, nil, map[string]string{"Accept": "text/calendar"}, "")
	switch {
	case err != nil:
		return "", err
	case resp.status == 404:
		return "", fail("notFound", "Nothing at %s", target)
	case resp.status >= 400:
		return "", fail("server", "GET %s: HTTP %d", target, resp.status)
	}
	return strings.ToValidUTF8(string(resp.body), "�"), nil
}

func discoverFeed(ctx context.Context, d *dav, target string) ([]Info, error) {
	text, err := fetchFeed(ctx, d, target)
	if err != nil {
		return nil, err
	}
	cal, err := ical.Parse(text)
	if err != nil {
		return nil, fail("parse", "Not an iCalendar feed: %v", err)
	}
	name := cal.Text("X-WR-CALNAME")
	if name == "" {
		u, _ := url.Parse(target)
		name = u.Host
	}
	color := cal.Text("X-APPLE-CALENDAR-COLOR")
	if len(color) > 7 {
		color = color[:7]
	}
	return []Info{{Href: target, Name: name, Color: color, Components: []string{"VEVENT"}, ReadOnly: true}}, nil
}

// failure is a calendar operation's failure as the shell shows it: code
// is one of auth, network, notFound, notCalendar, conflict, server,
// parse, noPassword, readOnly (CalendarManager.errorText)
type failure struct{ code, message string }

func (f *failure) Error() string { return f.message }

func fail(code, format string, args ...any) error {
	return &failure{code: code, message: fmt.Sprintf(format, args...)}
}

func codeOf(err error) string {
	if f, ok := err.(*failure); ok {
		return f.code
	}
	return ""
}
