// Package markets is the shell's stock and crypto prices, the `markets`
// polled topic (MarketsManager), with `markets.search` and
// `markets.history` for the watchlist card and the detail chart. Prices
// come from Yahoo's chart API (no key: stocks, ETFs, indices, FX and
// crypto) and, for coins Yahoo doesn't list, CoinGecko's. The last
// prices are kept in a state file, so the bar has them at once after a
// restart; a symbol whose market is closed is fetched again only hourly
// (pauseWhenClosed), and a host that answers 429 or 5xx is left alone
// for a while, its symbols keeping their last prices.
package markets

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/topics"
)

// Where prices come from.
const (
	YahooChartURL      = "https://query1.finance.yahoo.com/v8/finance/chart/"
	YahooSearchURL     = "https://query2.finance.yahoo.com/v1/finance/search"
	CoinGeckoMarketURL = "https://api.coingecko.com/api/v3/coins/markets"
	CoinGeckoChartURL  = "https://api.coingecko.com/api/v3/coins/"
	CoinGeckoSearchURL = "https://api.coingecko.com/api/v3/search"
)

// The sources a symbol can come from.
const (
	SourceYahoo     = "yahoo"
	SourceCoinGecko = "coingecko"
)

const (
	timeout = 15 * time.Second
	maxBody = 4 << 20
	// Yahoo symbols fetched at once
	workers = 4
	// A closed market's symbol is fetched again after this
	closedRecheck = time.Hour
	// A host that refused is left alone this long, doubling per refusal
	backoffMin, backoffMax = time.Minute, 30 * time.Minute
	// Yahoo's browsers-only hosts answer a plain agent with 429
	userAgent = "Mozilla/5.0 (X11; Linux x86_64) axiom"
)

// Symbol is one watched symbol: Yahoo's ticker ("AAPL", "BTC-USD",
// "^GSPC") or CoinGecko's coin id ("bitcoin").
type Symbol struct {
	Symbol string `json:"symbol"`
	Source string `json:"source"` // "yahoo" (default) or "coingecko"
}

// Request is the Markets settings, as the shell sends them.
type Request struct {
	Symbols []Symbol `json:"symbols"`
	// The portfolio's currency: CoinGecko's prices are in it, and with
	// Convert each other quote's currency gets its rate to it
	BaseCurrency    string `json:"baseCurrency"`
	Convert         bool   `json:"convert"`
	PauseWhenClosed bool   `json:"pauseWhenClosed"`
}

// Quote is one symbol's price and its day.
type Quote struct {
	Symbol   string  `json:"symbol"`
	Source   string  `json:"source"`
	Name     string  `json:"name"`
	Kind     string  `json:"kind"` // equity, etf, index, crypto, fx, future, fund, other
	Currency string  `json:"currency"`
	Exchange string  `json:"exchange"`
	Price    float64 `json:"price"`
	// The previous session's close (crypto: the price 24 hours ago)
	PrevClose     float64 `json:"prevClose"`
	Change        float64 `json:"change"`
	ChangePercent float64 `json:"changePercent"`
	DayHigh       float64 `json:"dayHigh"`
	DayLow        float64 `json:"dayLow"`
	// pre, regular, post or closed (crypto: always regular)
	MarketState string `json:"marketState"`
	// The points' time axis (unix seconds): the chart's regular session
	// (crypto: the last 24 hours)
	SessionStart int64 `json:"sessionStart"`
	SessionEnd   int64 `json:"sessionEnd"`
	// The market's current (or next) regular session, for MarketState
	// (0 for crypto)
	OpenAt  int64 `json:"openAt"`
	CloseAt int64 `json:"closeAt"`
	// [unix seconds, price], oldest first
	Points [][2]float64 `json:"points"`
	// When it was fetched (unix ms)
	UpdatedAt int64 `json:"updatedAt"`
	// Stale: the last fetch failed and these are older prices
	Stale bool `json:"stale"`
	// Error is why there's no price ("" when there is)
	Error string `json:"error"`

	// The pre and post sessions, for MarketState
	PreStart int64 `json:"preStart"`
	PostEnd  int64 `json:"postEnd"`
}

// State is every requested symbol's quote, keyed by Key.
type State struct {
	Quotes map[string]*Quote `json:"quotes"`
	// Each quote currency's rate to the base currency (with Convert)
	FX           map[string]float64 `json:"fx"`
	BaseCurrency string             `json:"baseCurrency"`
	// UpdatedAt is the newest quote's time (unix ms)
	UpdatedAt int64 `json:"updatedAt"`
	// Error is set when no symbol has a price
	Error string `json:"error"`
}

// Key is a symbol's key in State.Quotes: Yahoo's symbol, or
// "coingecko:<id>".
func Key(s Symbol) string {
	if s.Source == SourceCoinGecko {
		return SourceCoinGecko + ":" + s.Symbol
	}
	return s.Symbol
}

// Options are where the source fetches from; zero values are the real
// ones.
type Options struct {
	YahooChart, YahooSearch                          string
	CoinGeckoMarket, CoinGeckoChart, CoinGeckoSearch string
	Client                                           *http.Client
	Now                                              func() time.Time
	Log                                              *slog.Logger
	// StateFile keeps the quotes across restarts ("" keeps nothing)
	StateFile string
}

func (o Options) withDefaults() Options {
	def := func(s *string, v string) {
		if *s == "" {
			*s = v
		}
	}
	def(&o.YahooChart, YahooChartURL)
	def(&o.YahooSearch, YahooSearchURL)
	def(&o.CoinGeckoMarket, CoinGeckoMarketURL)
	def(&o.CoinGeckoChart, CoinGeckoChartURL)
	def(&o.CoinGeckoSearch, CoinGeckoSearchURL)
	if o.Client == nil {
		o.Client = &http.Client{Timeout: timeout}
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return o
}

// Markets fetches prices; one serves the topic, the search and the
// history.
type Markets struct {
	o  Options
	mu sync.Mutex
	// Every quote fetched (also unrequested ones, so a symbol removed and
	// added back keeps its prices), keyed by Key
	cache map[string]*Quote
	// FX rates by "<CUR><BASE>"
	fx map[string]*Quote
	// Hosts refusing, and until when (under bmu: the search and the
	// history fetch without mu)
	bmu     sync.Mutex
	backoff map[string]*hostBackoff
	// The last failure logged (each said once)
	failed string
	loaded bool
}

type hostBackoff struct {
	until    time.Time
	failures int
}

// New is a Markets fetching through o.
func New(o Options) *Markets {
	return &Markets{o: o.withDefaults(), cache: map[string]*Quote{}, fx: map[string]*Quote{}, backoff: map[string]*hostBackoff{}}
}

// Source is the `markets` topic.
func (m *Markets) Source() topics.Source {
	return topics.Source{
		Name:    "markets",
		Floor:   topics.MinInterval,
		Default: 2 * time.Minute,
		Request: reflect.TypeFor[Request](),
		State:   reflect.TypeFor[State](),
		Fetch: func(ctx context.Context, requests []json.RawMessage) (any, error) {
			// The settings are global: every subscriber asks the same
			var r Request
			if len(requests) > 0 {
				json.Unmarshal(requests[0], &r)
			}
			return m.State(ctx, r)
		},
	}
}

// State fetches r's symbols that are due and returns every one's quote.
func (m *Markets) State(ctx context.Context, r Request) (*State, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.load()
	now := m.o.Now()
	base := strings.ToUpper(strings.TrimSpace(r.BaseCurrency))
	if base == "" {
		base = "USD"
	}
	var yahoo, gecko, wanted []Symbol
	seen := map[string]bool{}
	for _, s := range r.Symbols {
		s.Symbol = strings.TrimSpace(s.Symbol)
		if s.Source != SourceCoinGecko {
			s.Source = SourceYahoo
		}
		if s.Symbol == "" || seen[Key(s)] {
			continue
		}
		seen[Key(s)] = true
		wanted = append(wanted, s)
		if !m.due(Key(s), r.PauseWhenClosed, now) {
			continue
		}
		if s.Source == SourceCoinGecko {
			gecko = append(gecko, s)
		} else {
			yahoo = append(yahoo, s)
		}
	}
	var errs []error
	errs = append(errs, m.fetchYahoo(ctx, yahoo)...)
	if len(gecko) > 0 {
		if err := m.fetchGecko(ctx, gecko, base, now); err != nil {
			errs = append(errs, err)
		}
	}
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}

	st := &State{Quotes: map[string]*Quote{}, FX: map[string]float64{}, BaseCurrency: base}
	for _, s := range wanted {
		q := m.cache[Key(s)]
		if q == nil {
			continue
		}
		c := *q
		c.MarketState = marketState(&c, now)
		st.Quotes[Key(s)] = &c
		st.UpdatedAt = max(st.UpdatedAt, c.UpdatedAt)
	}
	if r.Convert {
		errs = append(errs, m.convert(ctx, st, base, now)...)
	}
	m.report(errs)
	good := 0
	for _, q := range st.Quotes {
		if q.Error == "" {
			good++
		}
	}
	if good == 0 && len(errs) > 0 {
		st.Error = errs[0].Error()
	}
	m.save()
	return st, nil
}

// due: whether key's quote should be fetched now. A closed market's is
// fetched once after its close (for the final prices) and then hourly.
func (m *Markets) due(key string, pauseWhenClosed bool, now time.Time) bool {
	q := m.cache[key]
	if q == nil || q.Error != "" || q.Stale || !pauseWhenClosed || q.Kind == "crypto" || q.CloseAt == 0 {
		return true
	}
	t := now.Unix()
	if t >= q.OpenAt && t < q.CloseAt {
		return true
	}
	fetched := time.UnixMilli(q.UpdatedAt)
	if fetched.Unix() < q.CloseAt && t >= q.CloseAt {
		return true
	}
	return now.Sub(fetched) >= closedRecheck
}

// marketState is where q's market is at now.
func marketState(q *Quote, now time.Time) string {
	if q.Kind == "crypto" || q.CloseAt == 0 {
		return "regular"
	}
	t := now.Unix()
	switch {
	case t >= q.OpenAt && t < q.CloseAt:
		return "regular"
	case q.PreStart > 0 && t >= q.PreStart && t < q.OpenAt:
		return "pre"
	case q.PostEnd > 0 && t >= q.CloseAt && t < q.PostEnd:
		return "post"
	}
	return "closed"
}

// keep stores a fetched quote, or marks the cached one stale on err.
func (m *Markets) keep(key string, q *Quote, err error, s Symbol) {
	if err == nil {
		m.cache[key] = q
		return
	}
	if old := m.cache[key]; old != nil && old.Error == "" {
		old.Stale = true
		return
	}
	m.cache[key] = &Quote{Symbol: s.Symbol, Source: s.Source, Name: s.Symbol, Error: err.Error()}
}

func (m *Markets) report(errs []error) {
	msg := ""
	if len(errs) > 0 {
		msg = errors.Join(errs...).Error()
	}
	if msg != "" && msg != m.failed {
		m.o.Log.Warn("fetching market prices", "err", msg)
	}
	m.failed = msg
}

// errBackoff is a host being left alone.
type errBackoff struct{ host string }

func (e errBackoff) Error() string { return e.host + ": rate limited, retrying later" }

// get fetches u's JSON into v, minding the host's backoff.
func (m *Markets) get(ctx context.Context, u string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	host := req.URL.Host
	now := m.o.Now()
	if m.refused(host, now) {
		return errBackoff{host}
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", userAgent)
	resp, err := m.o.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	refused := resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500
	m.answered(host, refused, now)
	if refused {
		return fmt.Errorf("%s: HTTP %d", host, resp.StatusCode)
	}
	if resp.StatusCode == http.StatusNotFound {
		return errNotFound
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%s: HTTP %d", host, resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBody)).Decode(v); err != nil {
		return fmt.Errorf("%s: %w", host, err)
	}
	return nil
}

var errNotFound = errors.New("unknown symbol")

// refused: whether host is being left alone at now.
func (m *Markets) refused(host string, now time.Time) bool {
	m.bmu.Lock()
	defer m.bmu.Unlock()
	b := m.backoff[host]
	return b != nil && now.Before(b.until)
}

// answered notes host's answer: a refusal doubles its wait, anything
// else ends it.
func (m *Markets) answered(host string, refused bool, now time.Time) {
	m.bmu.Lock()
	defer m.bmu.Unlock()
	if !refused {
		delete(m.backoff, host)
		return
	}
	b := m.backoff[host]
	if b == nil {
		b = &hostBackoff{}
		m.backoff[host] = b
	}
	b.failures++
	b.until = now.Add(min(backoffMax, backoffMin<<min(b.failures-1, 10)))
}

type stored struct {
	Quotes map[string]*Quote `json:"quotes"`
	FX     map[string]*Quote `json:"fx"`
}

func (m *Markets) load() {
	if m.loaded {
		return
	}
	m.loaded = true
	if m.o.StateFile == "" {
		return
	}
	data, err := os.ReadFile(m.o.StateFile)
	if err != nil {
		return
	}
	var s stored
	if json.Unmarshal(data, &s) != nil {
		return
	}
	for k, q := range s.Quotes {
		if q != nil && q.Error == "" {
			m.cache[k] = q
		}
	}
	for k, q := range s.FX {
		if q != nil && q.Error == "" {
			m.fx[k] = q
		}
	}
}

func (m *Markets) save() {
	if m.o.StateFile == "" {
		return
	}
	s := stored{Quotes: map[string]*Quote{}, FX: m.fx}
	for k, q := range m.cache {
		if q.Error == "" {
			s.Quotes[k] = q
		}
	}
	data, err := json.Marshal(s)
	if err == nil {
		err = os.MkdirAll(filepath.Dir(m.o.StateFile), 0o700)
	}
	if err == nil {
		err = fsx.WriteFile(m.o.StateFile, append(data, '\n'), 0o600)
	}
	if err != nil {
		m.o.Log.Warn("saving market prices", "err", err)
	}
}
