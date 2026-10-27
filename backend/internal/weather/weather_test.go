package weather

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

const forecastReply = `{
	"current": {"temperature_2m": 12.3, "apparent_temperature": 10.1, "weather_code": 3, "is_day": 1, "wind_speed_10m": 14.2, "relative_humidity_2m": 80},
	"current_units": {"wind_speed_10m": "km/h"},
	"hourly": {"time": ["2026-10-27T14:00"], "temperature_2m": [12.5], "weather_code": [2], "is_day": [1]},
	"daily": {"time": ["2026-10-27"], "weather_code": [61], "temperature_2m_max": [14], "temperature_2m_min": [6]},
	"elevation": 40
}`

// fake answers each path with its status and body, and records the
// queries it was asked
type fake struct {
	mu      sync.Mutex
	replies map[string]string // path → body; a body "" is a 503
	asked   []string
	*httptest.Server
}

func newFake(t *testing.T, replies map[string]string) *fake {
	f := &fake{replies: replies}
	f.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.asked = append(f.asked, r.URL.Path+"?"+r.URL.RawQuery)
		body := f.replies[r.URL.Path]
		if body == "" {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte(body))
	}))
	t.Cleanup(f.Close)
	return f
}

func (f *fake) set(path, body string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.replies[path] = body
}

func (f *fake) calls(path string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, a := range f.asked {
		if strings.HasPrefix(a, path+"?") {
			n++
		}
	}
	return n
}

type clock struct{ now time.Time }

func (c *clock) Now() time.Time { return c.now }

func newFetcher(f *fake, c *clock) *fetcher {
	return &fetcher{o: Options{Forecast: f.URL + "/forecast", Geocode: f.URL + "/geo", IPInfo: f.URL + "/ipinfo", IPAPI: f.URL + "/ipapi", Client: http.DefaultClient, Now: c.Now}}
}

func TestPlace(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name    string
		req     Request
		replies map[string]string
		want    Place
		wantErr string
	}{
		{"coordinates", Request{Latitude: "52.5", Longitude: " 13.4"}, nil, Place{52.5, 13.4, "52.50, 13.40"}, ""},
		{"coordinates named", Request{Location: "Home", Latitude: "1", Longitude: "2"}, nil, Place{1, 2, "Home"}, ""},
		{"geocoded", Request{Location: "Berlin"}, map[string]string{"/geo": `{"results":[{"latitude":52.52,"longitude":13.41,"name":"Berlin","admin1":"Land Berlin","country_code":"DE"}]}`}, Place{52.52, 13.41, "Berlin, Land Berlin, DE"}, ""},
		{"unknown location", Request{Location: "Nowhere"}, map[string]string{"/geo": `{}`}, Place{}, `unknown location "Nowhere"`},
		{"ipinfo", Request{}, map[string]string{"/ipinfo": `{"loc":"40.7,-74.0","city":"New York","region":"New York"}`}, Place{40.7, -74, "New York, New York"}, ""},
		{"ipapi when ipinfo fails", Request{}, map[string]string{"/ipapi": `{"latitude":48.85,"longitude":2.35,"city":"Paris","region_code":"IDF"}`}, Place{48.85, 2.35, "Paris, IDF"}, ""},
		{"ipapi when ipinfo has no loc", Request{}, map[string]string{"/ipinfo": `{"bogon":true}`, "/ipapi": `{"latitude":0,"longitude":0}`}, Place{0, 0, ""}, ""},
		{"no IP location", Request{}, map[string]string{"/ipapi": `{"error":true}`}, Place{}, "no location"},
		{"both IP services down", Request{}, nil, Place{}, "HTTP 503"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if tc.replies == nil {
				tc.replies = map[string]string{}
			}
			f := newFake(t, tc.replies)
			got, err := newFetcher(f, &clock{time.Unix(0, 0)}).resolve(context.Background(), tc.req)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("err = %v, want %q", err, tc.wantErr)
				}
				return
			}
			if err != nil || *got != tc.want {
				t.Fatalf("got %+v, %v; want %+v", got, err, tc.want)
			}
		})
	}
}

// A named place is looked up once; an IP's again after an hour, keeping
// the last one when that lookup fails.
func TestPlaceCache(t *testing.T) {
	t.Parallel()
	f := newFake(t, map[string]string{
		"/geo":    `{"results":[{"latitude":1,"longitude":2,"name":"A"}]}`,
		"/ipinfo": `{"loc":"3,4","city":"B"}`,
	})
	c := &clock{time.Unix(0, 0)}
	w := newFetcher(f, c)
	ctx := context.Background()
	for range 2 {
		w.resolve(ctx, Request{Location: "A"})
	}
	if n := f.calls("/geo"); n != 1 {
		t.Fatalf("geocoded %d times, want 1", n)
	}
	w.resolve(ctx, Request{})
	c.now = c.now.Add(30 * time.Minute)
	w.resolve(ctx, Request{})
	if n := f.calls("/ipinfo"); n != 1 {
		t.Fatalf("IP looked up %d times within the hour, want 1", n)
	}
	c.now = c.now.Add(time.Hour)
	f.set("/ipinfo", "")
	p, err := w.resolve(ctx, Request{})
	if err != nil || p.Name != "B" || f.calls("/ipinfo") != 2 {
		t.Fatalf("after the hour: %+v, %v, %d lookups; want the last place after a second lookup", p, err, f.calls("/ipinfo"))
	}
}

func TestFetch(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, units, wantQuery string
	}{
		{"celsius", "celsius", "temperature_unit=celsius&timezone=auto&wind_speed_unit=kmh"},
		{"fahrenheit", "fahrenheit", "temperature_unit=fahrenheit&timezone=auto&wind_speed_unit=mph"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFake(t, map[string]string{"/forecast": forecastReply})
			req := Request{Latitude: "1.5", Longitude: "2", Units: tc.units}
			st, err := newFetcher(f, &clock{}).fetch(context.Background(), req)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.HasSuffix(f.asked[0], tc.wantQuery) || !strings.Contains(f.asked[0], "latitude=1.5&longitude=2") {
				t.Errorf("asked %s", f.asked[0])
			}
			if st.Request != req || st.Place.Name != "1.50, 2.00" {
				t.Errorf("state is for %+v at %+v", st.Request, st.Place)
			}
			// The shell reads Open-Meteo's field names, and only those
			data, _ := json.Marshal(st)
			var got map[string]any
			json.Unmarshal(data, &got)
			weather := got["weather"].(map[string]any)
			if weather["current"].(map[string]any)["temperature_2m"] != 12.3 || weather["daily"].(map[string]any)["weather_code"].([]any)[0] != 61.0 || weather["current_units"].(map[string]any)["wind_speed_10m"] != "km/h" {
				t.Errorf("state %s", data)
			}
			if _, ok := weather["elevation"]; ok {
				t.Errorf("state carries a field the shell doesn't read: %s", data)
			}
		})
	}
}

func TestFetchFails(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ name, reply, want string }{
		{"down", "", "HTTP 503"},
		{"not JSON", "<html>", "invalid character"},
		{"no current weather", `{"daily":{}}`, "no current weather"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			f := newFake(t, map[string]string{"/forecast": tc.reply})
			_, err := newFetcher(f, &clock{}).fetch(context.Background(), Request{Latitude: "1", Longitude: "2"})
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want %q", err, tc.want)
			}
		})
	}
}

// The source fetches for the first request (every subscriber sends the
// same settings).
func TestSource(t *testing.T) {
	t.Parallel()
	f := newFake(t, map[string]string{"/forecast": forecastReply})
	src := Source(Options{Forecast: f.URL + "/forecast"})
	if src.Name != "weather" {
		t.Fatal(src.Name)
	}
	st, err := src.Fetch(context.Background(), []json.RawMessage{json.RawMessage(`{"latitude":"5","longitude":"6","units":"fahrenheit","interval":900000}`)})
	if err != nil {
		t.Fatal(err)
	}
	if s := st.(*State); s.Units != "fahrenheit" || s.Place.Latitude != 5 {
		t.Fatalf("%+v", s)
	}
}
