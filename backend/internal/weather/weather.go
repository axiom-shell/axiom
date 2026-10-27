// Package weather is the weather for the shell, the `weather` polled
// topic (WeatherManager): Open-Meteo's forecast (no API key) for one
// place, from the Weather settings' coordinates, else their location
// (geocoded by Open-Meteo), else the machine's IP (ipinfo.io, then
// ipapi.co, as either may rate limit). A failed fetch is an error the hub
// logs once, so the shell keeps the last good weather.
package weather

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Where weather and places come from.
const (
	ForecastURL = "https://api.open-meteo.com/v1/forecast"
	GeocodeURL  = "https://geocoding-api.open-meteo.com/v1/search"
	IPInfoURL   = "https://ipinfo.io/json"
	IPAPIURL    = "https://ipapi.co/json/"
)

const (
	timeout = 15 * time.Second
	maxBody = 1 << 20
	// A place from the IP is looked up again after this (the machine may
	// have moved); a named one never is
	ipPlaceTTL = time.Hour
)

// Request is the Weather settings, as the shell sends them.
type Request struct {
	Location  string `json:"location"`
	Latitude  string `json:"latitude"`
	Longitude string `json:"longitude"`
	Units     string `json:"units"` // "celsius" or "fahrenheit"
}

// Place is where the weather is for.
type Place struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
	Name      string  `json:"name"`
}

// Forecast is the part of Open-Meteo's answer the shell shows, under its
// field names: current conditions, 12 hours and 5 days.
type Forecast struct {
	Current *struct {
		Temperature         float64 `json:"temperature_2m"`
		ApparentTemperature float64 `json:"apparent_temperature"`
		WeatherCode         int     `json:"weather_code"`
		IsDay               int     `json:"is_day"`
		WindSpeed           float64 `json:"wind_speed_10m"`
		Humidity            float64 `json:"relative_humidity_2m"`
	} `json:"current"`
	CurrentUnits struct {
		WindSpeed string `json:"wind_speed_10m"`
	} `json:"current_units"`
	Hourly struct {
		Time        []string  `json:"time"`
		Temperature []float64 `json:"temperature_2m"`
		WeatherCode []int     `json:"weather_code"`
		IsDay       []int     `json:"is_day"`
	} `json:"hourly"`
	Daily struct {
		Time        []string  `json:"time"`
		WeatherCode []int     `json:"weather_code"`
		Max         []float64 `json:"temperature_2m_max"`
		Min         []float64 `json:"temperature_2m_min"`
	} `json:"daily"`
}

// State is the weather for one request, which it carries so the shell
// drops a state fetched for settings it no longer has.
type State struct {
	Request
	Place   Place    `json:"place"`
	Weather Forecast `json:"weather"`
}

// Options are where the source fetches from; zero values are the real
// ones.
type Options struct {
	Forecast, Geocode, IPInfo, IPAPI string
	Client                           *http.Client
	Now                              func() time.Time
}

// Source is the `weather` topic.
func Source(o Options) topics.Source {
	if o.Forecast == "" {
		o.Forecast = ForecastURL
	}
	if o.Geocode == "" {
		o.Geocode = GeocodeURL
	}
	if o.IPInfo == "" {
		o.IPInfo = IPInfoURL
	}
	if o.IPAPI == "" {
		o.IPAPI = IPAPIURL
	}
	if o.Client == nil {
		o.Client = &http.Client{Timeout: timeout}
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	w := &fetcher{o: o}
	return topics.Source{
		Name:    "weather",
		Floor:   topics.MinInterval,
		Default: 15 * time.Minute,
		Request: reflect.TypeFor[Request](),
		State:   reflect.TypeFor[State](),
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			// The settings are global: every subscriber asks the same
			var r Request
			if len(requests) > 0 {
				json.Unmarshal(requests[0], &r)
			}
			return w.fetch(ctx, r)
		},
	}
}

type fetcher struct {
	o Options
	// A loop stopped and started again can briefly overlap the old one
	mu sync.Mutex
	// The place last resolved, for placeKey, and when
	place    *Place
	placeKey string
	placeAt  time.Time
}

func (w *fetcher) fetch(ctx context.Context, r Request) (*State, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	place, err := w.resolve(ctx, r)
	if err != nil {
		return nil, err
	}
	units, wind := "celsius", "kmh"
	if r.Units == "fahrenheit" {
		units, wind = "fahrenheit", "mph"
	}
	q := url.Values{
		"latitude":         {strconv.FormatFloat(place.Latitude, 'f', -1, 64)},
		"longitude":        {strconv.FormatFloat(place.Longitude, 'f', -1, 64)},
		"current":          {"temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"},
		"hourly":           {"temperature_2m,weather_code,is_day"},
		"forecast_hours":   {"12"},
		"daily":            {"weather_code,temperature_2m_max,temperature_2m_min"},
		"timezone":         {"auto"},
		"forecast_days":    {"5"},
		"temperature_unit": {units},
		"wind_speed_unit":  {wind},
	}
	st := &State{Request: r, Place: *place}
	if err := w.get(ctx, w.o.Forecast+"?"+q.Encode(), &st.Weather); err != nil {
		return nil, err
	}
	if st.Weather.Current == nil {
		return nil, fmt.Errorf("open-meteo: no current weather")
	}
	return st, nil
}

// resolve is the request's place: its coordinates, else the one looked
// up for it before (an IP's for an hour), else a new lookup. A failed
// lookup falls back on the last place for the same settings.
func (w *fetcher) resolve(ctx context.Context, r Request) (*Place, error) {
	lat, errLat := strconv.ParseFloat(strings.TrimSpace(r.Latitude), 64)
	lon, errLon := strconv.ParseFloat(strings.TrimSpace(r.Longitude), 64)
	if errLat == nil && errLon == nil {
		name := r.Location
		if name == "" {
			name = fmt.Sprintf("%.2f, %.2f", lat, lon)
		}
		return &Place{Latitude: lat, Longitude: lon, Name: name}, nil
	}
	key := r.Location
	now := w.o.Now()
	if w.place != nil && w.placeKey == key && (key != "" || now.Sub(w.placeAt) < ipPlaceTTL) {
		return w.place, nil
	}
	var place *Place
	var err error
	if key != "" {
		place, err = w.geocode(ctx, key)
	} else {
		place, err = w.fromIP(ctx)
	}
	if err != nil {
		if w.place != nil && w.placeKey == key {
			return w.place, nil
		}
		return nil, err
	}
	w.place, w.placeKey, w.placeAt = place, key, now
	return place, nil
}

func (w *fetcher) geocode(ctx context.Context, location string) (*Place, error) {
	var reply struct {
		Results []struct {
			Latitude    float64 `json:"latitude"`
			Longitude   float64 `json:"longitude"`
			Name        string  `json:"name"`
			Admin1      string  `json:"admin1"`
			CountryCode string  `json:"country_code"`
		} `json:"results"`
	}
	q := url.Values{"count": {"1"}, "name": {location}}
	if err := w.get(ctx, w.o.Geocode+"?"+q.Encode(), &reply); err != nil {
		return nil, err
	}
	if len(reply.Results) == 0 {
		return nil, fmt.Errorf("unknown location %q", location)
	}
	r := reply.Results[0]
	return &Place{Latitude: r.Latitude, Longitude: r.Longitude, Name: join(r.Name, r.Admin1, r.CountryCode)}, nil
}

// fromIP asks ipinfo.io, then ipapi.co.
func (w *fetcher) fromIP(ctx context.Context) (*Place, error) {
	var info struct {
		Loc    string `json:"loc"`
		City   string `json:"city"`
		Region string `json:"region"`
	}
	err := w.get(ctx, w.o.IPInfo, &info)
	if err == nil {
		lat, lon, ok := strings.Cut(info.Loc, ",")
		la, errLat := strconv.ParseFloat(lat, 64)
		lo, errLon := strconv.ParseFloat(lon, 64)
		if ok && errLat == nil && errLon == nil {
			return &Place{Latitude: la, Longitude: lo, Name: join(info.City, info.Region)}, nil
		}
	}
	var api struct {
		Latitude   *float64 `json:"latitude"`
		Longitude  *float64 `json:"longitude"`
		City       string   `json:"city"`
		RegionCode string   `json:"region_code"`
	}
	if err := w.get(ctx, w.o.IPAPI, &api); err != nil {
		return nil, err
	}
	if api.Latitude == nil || api.Longitude == nil {
		return nil, fmt.Errorf("no location for this machine's IP")
	}
	return &Place{Latitude: *api.Latitude, Longitude: *api.Longitude, Name: join(api.City, api.RegionCode)}, nil
}

// get fetches u's JSON into v.
func (w *fetcher) get(ctx context.Context, u string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "axiom")
	resp, err := w.o.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	host := req.URL.Host
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s: HTTP %d", host, resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBody)).Decode(v); err != nil {
		return fmt.Errorf("%s: %w", host, err)
	}
	return nil
}

func join(parts ...string) string {
	var out []string
	for _, p := range parts {
		if p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, ", ")
}
