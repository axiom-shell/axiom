package markets

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// The fake session: 14:30–21:00 UTC on 2026-11-05.
var (
	sessionStart = time.Date(2026, 11, 5, 14, 30, 0, 0, time.UTC)
	sessionEnd   = time.Date(2026, 11, 5, 21, 0, 0, 0, time.UTC)
)

type fakeQuote struct {
	price, prev float64
	currency    string
	kind        string
	// The current trading period is already the next day's (Yahoo
	// after a close)
	nextDay bool
}

// fakeServer is Yahoo and CoinGecko in one: /chart/<symbol>,
// /search, /markets, /coins/<id>/market_chart, /gsearch.
type fakeServer struct {
	srv    *httptest.Server
	mu     sync.Mutex
	quotes map[string]fakeQuote
	// Hits per path
	hits map[string]int
	// A status every path answers with (0: normal)
	status int
	// Each chart asked for, "<symbol>:<range>"
	ranges []string
}

func newFake(t *testing.T) *fakeServer {
	f := &fakeServer{hits: map[string]int{}, quotes: map[string]fakeQuote{
		"AAPL":     {price: 110, prev: 100, currency: "USD", kind: "EQUITY"},
		"SAP.DE":   {price: 200, prev: 210, currency: "EUR", kind: "EQUITY"},
		"VOD.L":    {price: 70, prev: 70, currency: "GBp", kind: "EQUITY"},
		"BTC-USD":  {price: 50000, prev: 48000, currency: "USD", kind: "CRYPTOCURRENCY"},
		"NEXT":     {price: 10, prev: 9, currency: "USD", kind: "EQUITY", nextDay: true},
		"EURUSD=X": {price: 1.1, prev: 1.1, currency: "USD", kind: "CURRENCY"},
		"GBPUSD=X": {price: 1.3, prev: 1.3, currency: "USD", kind: "CURRENCY"},
	}}
	f.srv = httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeServer) hit(path string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.hits[path]
}

func (f *fakeServer) serve(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	f.hits[r.URL.Path]++
	status := f.status
	f.mu.Unlock()
	if status != 0 {
		w.WriteHeader(status)
		return
	}
	switch {
	case strings.HasPrefix(r.URL.Path, "/chart/"):
		sym := strings.TrimPrefix(r.URL.Path, "/chart/")
		q, ok := f.quotes[sym]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			fmt.Fprint(w, `{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}`)
			return
		}
		f.mu.Lock()
		f.ranges = append(f.ranges, sym+":"+r.URL.Query().Get("range"))
		f.mu.Unlock()
		start, end := sessionStart.Unix(), sessionEnd.Unix()
		if q.kind == "CRYPTOCURRENCY" {
			start, end = time.Date(2026, 11, 5, 0, 0, 0, 0, time.UTC).Unix(), time.Date(2026, 11, 5, 23, 59, 0, 0, time.UTC).Unix()
		}
		cur := start
		if q.nextDay {
			cur = start + 86400
		}
		// Crypto's 5 days: a point two days ago, then the day's
		ts := fmt.Sprintf("%d,%d,%d", start, start+300, start+600)
		closes := fmt.Sprintf("%v,null,%v", q.prev, q.price)
		if r.URL.Query().Get("range") == "5d" {
			ts = fmt.Sprintf("%d,%d,%d,%d", start-2*86400, start, start+300, start+600)
			closes = fmt.Sprintf("1,%v,null,%v", q.prev, q.price)
		}
		fmt.Fprintf(w, `{"chart":{"result":[{"meta":{"currency":%q,"symbol":%q,"fullExchangeName":"NasdaqGS","instrumentType":%q,
			"regularMarketPrice":%v,"chartPreviousClose":%v,"regularMarketDayHigh":%v,"regularMarketDayLow":%v,"shortName":"Name of %s",
			"currentTradingPeriod":{"pre":{"start":%d,"end":%d},"regular":{"start":%d,"end":%d},"post":{"start":%d,"end":%d}},
			"tradingPeriods":[[{"start":%d,"end":%d}]]},
			"timestamp":[%s],"indicators":{"quote":[{"close":[%s]}]}}],"error":null}}`,
			q.currency, sym, q.kind, q.price, q.prev, q.price+1, q.prev-1, sym,
			cur-3600, cur, cur, cur+end-start, cur+end-start, cur+end-start+3600,
			start, end, ts, closes)
	case r.URL.Path == "/search":
		fmt.Fprint(w, `{"quotes":[{"symbol":"AAPL","shortname":"Apple","longname":"Apple Inc.","quoteType":"EQUITY","exchDisp":"NASDAQ"},{"shortname":"no symbol"}]}`)
	case r.URL.Path == "/gsearch":
		fmt.Fprint(w, `{"coins":[{"id":"bitcoin","symbol":"btc","name":"Bitcoin","market_cap_rank":1},{"id":"x","symbol":"x","name":"X"}]}`)
	case r.URL.Path == "/markets":
		ids := strings.Split(r.URL.Query().Get("ids"), ",")
		var out []string
		for _, id := range ids {
			if id == "bitcoin" {
				out = append(out, `{"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":100,"price_change_24h":-10,
					"price_change_percentage_24h":-9.09,"high_24h":115,"low_24h":95,"last_updated":"2026-11-05T12:00:00Z",
					"sparkline_in_7d":{"price":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30]}}`)
			}
		}
		fmt.Fprintf(w, "[%s]", strings.Join(out, ","))
	case strings.HasSuffix(r.URL.Path, "/market_chart"):
		fmt.Fprint(w, `{"prices":[[1000000,5],[2000000,9],[3000000,7]]}`)
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) Now() time.Time      { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Add(d time.Duration) { c.mu.Lock(); c.t = c.t.Add(d); c.mu.Unlock() }

func newMarkets(f *fakeServer, c *clock, stateFile string) *Markets {
	u := f.srv.URL
	return New(Options{
		YahooChart: u + "/chart/", YahooSearch: u + "/search",
		CoinGeckoMarket: u + "/markets", CoinGeckoChart: u + "/coins/", CoinGeckoSearch: u + "/gsearch",
		Client: f.srv.Client(), Now: c.Now, StateFile: stateFile,
	})
}

func syms(s ...string) []Symbol {
	out := make([]Symbol, len(s))
	for i, v := range s {
		src, sym, ok := strings.Cut(v, ":")
		if !ok {
			src, sym = SourceYahoo, v
		}
		out[i] = Symbol{Symbol: sym, Source: src}
	}
	return out
}

func TestYahooQuote(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart.Add(time.Hour)}
	st, err := newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("AAPL", "BTC-USD")})
	if err != nil || st.Error != "" {
		t.Fatalf("State: %v %q", err, st.Error)
	}
	q := st.Quotes["AAPL"]
	if q == nil {
		t.Fatalf("no AAPL in %v", st.Quotes)
	}
	want := Quote{Symbol: "AAPL", Source: "yahoo", Name: "Name of AAPL", Kind: "equity", Currency: "USD", Exchange: "NasdaqGS",
		Price: 110, PrevClose: 100, Change: 10, ChangePercent: 10, DayHigh: 111, DayLow: 99, MarketState: "regular",
		SessionStart: sessionStart.Unix(), SessionEnd: sessionEnd.Unix(), OpenAt: sessionStart.Unix(), CloseAt: sessionEnd.Unix(),
		PreStart: sessionStart.Unix() - 3600, PostEnd: sessionEnd.Unix() + 3600}
	got := *q
	if len(got.Points) != 2 || got.Points[1][1] != 110 {
		t.Errorf("points %v: want the null one skipped", got.Points)
	}
	got.Points, got.UpdatedAt = nil, 0
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Errorf("quote\n got %+v\nwant %+v", got, want)
	}
	if st.Quotes["BTC-USD"].Kind != "crypto" {
		t.Errorf("BTC-USD kind %q", st.Quotes["BTC-USD"].Kind)
	}
}

func TestCryptoDayIsTheLast24Hours(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	// 15:30 UTC: the window starts 15:30 the day before
	now := sessionStart.Add(time.Hour)
	c := &clock{t: now}
	m := newMarkets(f, c, "")
	st, _ := m.State(context.Background(), Request{Symbols: syms("BTC-USD")})
	q := st.Quotes["BTC-USD"]
	if q.SessionEnd-q.SessionStart != 86400 || q.SessionEnd != now.Unix() {
		t.Errorf("session %d–%d, want the 24 hours to now", q.SessionStart, q.SessionEnd)
	}
	// The point two days ago starts the window, the rest are in it
	if len(q.Points) != 3 || q.Points[0][1] != 1 {
		t.Errorf("points %v", q.Points)
	}
	if q.PrevClose != 1 || q.Change != 49999 || q.DayLow != 1 || q.DayHigh != 50000 {
		t.Errorf("prev %v change %v range %v–%v, from the window", q.PrevClose, q.Change, q.DayLow, q.DayHigh)
	}
	c.Add(time.Minute)
	m.State(context.Background(), Request{Symbols: syms("BTC-USD")})
	f.mu.Lock()
	got := strings.Join(f.ranges, " ")
	f.mu.Unlock()
	if got != "BTC-USD:1d BTC-USD:5d BTC-USD:5d" {
		t.Errorf("charts asked %q: want the day once (to learn it's crypto), then 5 days", got)
	}
}

func TestClosedSessionIsTheChartsOwn(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionEnd.Add(5 * time.Hour)}
	st, _ := newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("NEXT")})
	q := st.Quotes["NEXT"]
	if q.SessionStart != sessionStart.Unix() || q.OpenAt != sessionStart.Unix()+86400 {
		t.Errorf("session %d, open %d: want the chart's day and the next session", q.SessionStart, q.OpenAt)
	}
	if q.MarketState != "pre" && q.MarketState != "closed" {
		t.Errorf("state %q", q.MarketState)
	}
}

func TestMarketState(t *testing.T) {
	t.Parallel()
	q := &Quote{Kind: "equity", PreStart: 100, OpenAt: 200, CloseAt: 300, PostEnd: 400}
	for _, tc := range []struct {
		at   int64
		kind string
		want string
	}{
		{50, "equity", "closed"}, {150, "equity", "pre"}, {250, "equity", "regular"},
		{350, "equity", "post"}, {450, "equity", "closed"}, {450, "crypto", "regular"},
	} {
		c := *q
		c.Kind = tc.kind
		if got := marketState(&c, time.Unix(tc.at, 0)); got != tc.want {
			t.Errorf("at %d (%s): %q, want %q", tc.at, tc.kind, got, tc.want)
		}
	}
}

func TestClosedMarketIsFetchedHourly(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionEnd.Add(time.Minute)}
	m := newMarkets(f, c, "")
	r := Request{Symbols: syms("AAPL", "BTC-USD"), PauseWhenClosed: true}
	for i, tc := range []struct {
		after     time.Duration
		aapl, btc int
	}{
		{0, 1, 2},                // first: both (crypto asked again for its 24 hours)
		{10 * time.Minute, 1, 3}, // closed: only crypto
		{time.Hour, 2, 4},        // an hour on: again
	} {
		c.Add(tc.after)
		if _, err := m.State(context.Background(), r); err != nil {
			t.Fatal(err)
		}
		if a, b := f.hit("/chart/AAPL"), f.hit("/chart/BTC-USD"); a != tc.aapl || b != tc.btc {
			t.Errorf("step %d: AAPL %d BTC %d fetches, want %d %d", i, a, b, tc.aapl, tc.btc)
		}
	}
	// Without the pause, every time
	r.PauseWhenClosed = false
	m.State(context.Background(), r)
	if a := f.hit("/chart/AAPL"); a != 3 {
		t.Errorf("unpaused: AAPL fetched %d times, want 3", a)
	}
}

func TestFinalCloseIsFetched(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionEnd.Add(-time.Minute)}
	m := newMarkets(f, c, "")
	r := Request{Symbols: syms("AAPL"), PauseWhenClosed: true}
	m.State(context.Background(), r)
	c.Add(5 * time.Minute) // closed now, but last fetched while open
	m.State(context.Background(), r)
	c.Add(5 * time.Minute)
	m.State(context.Background(), r)
	if a := f.hit("/chart/AAPL"); a != 2 {
		t.Errorf("AAPL fetched %d times, want 2 (once open, once for the close)", a)
	}
}

func TestBackoffKeepsLastPrices(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart.Add(time.Hour)}
	m := newMarkets(f, c, "")
	r := Request{Symbols: syms("AAPL")}
	m.State(context.Background(), r)
	f.mu.Lock()
	f.status = http.StatusTooManyRequests
	f.mu.Unlock()
	c.Add(time.Minute)
	st, _ := m.State(context.Background(), r)
	if q := st.Quotes["AAPL"]; q == nil || !q.Stale || q.Price != 110 || st.Error != "" {
		t.Errorf("after a 429: %+v %q, want the last price, stale", q, st.Error)
	}
	before := f.hit("/chart/AAPL")
	c.Add(30 * time.Second)
	m.State(context.Background(), r)
	if f.hit("/chart/AAPL") != before {
		t.Error("fetched again while backing off")
	}
	f.mu.Lock()
	f.status = 0
	f.mu.Unlock()
	c.Add(time.Minute)
	st, _ = m.State(context.Background(), r)
	if q := st.Quotes["AAPL"]; q.Stale {
		t.Error("still stale after the backoff ended")
	}
}

func TestPartialErrors(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart.Add(time.Hour)}
	st, _ := newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("AAPL", "NOPE", "coingecko:nocoin")})
	if st.Error != "" {
		t.Errorf("state error %q with AAPL good", st.Error)
	}
	if st.Quotes["NOPE"].Error == "" || st.Quotes["coingecko:nocoin"].Error == "" {
		t.Errorf("unknown symbols carry no error: %+v %+v", st.Quotes["NOPE"], st.Quotes["coingecko:nocoin"])
	}
	st, _ = newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("NOPE")})
	if st.Error == "" {
		t.Error("no state error with no price at all")
	}
}

func TestCoinGecko(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart}
	st, _ := newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("coingecko:bitcoin"), BaseCurrency: "eur"})
	q := st.Quotes["coingecko:bitcoin"]
	if q == nil || q.Price != 100 || q.PrevClose != 110 || q.Currency != "EUR" || q.Kind != "crypto" {
		t.Fatalf("quote %+v", q)
	}
	if len(q.Points) != 25 || q.Points[24][1] != 30 || q.Points[0][1] != 6 {
		t.Errorf("points %v: want the last 25 hourly", q.Points)
	}
	if got := q.SessionEnd - q.SessionStart; got != 86400 {
		t.Errorf("session %ds, want a day", got)
	}
}

func TestConvert(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart.Add(time.Hour)}
	st, _ := newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("AAPL", "SAP.DE", "VOD.L"), Convert: true})
	want := map[string]float64{"EUR": 1.1, "GBp": 0.013}
	for cur, rate := range want {
		if got := st.FX[cur]; fmt.Sprintf("%.4f", got) != fmt.Sprintf("%.4f", rate) {
			t.Errorf("%s rate %v, want %v", cur, got, rate)
		}
	}
	if _, ok := st.FX["USD"]; ok {
		t.Error("a rate for the base currency")
	}
	st, _ = newMarkets(f, c, "").State(context.Background(), Request{Symbols: syms("SAP.DE")})
	if len(st.FX) != 0 {
		t.Errorf("rates %v without Convert", st.FX)
	}
}

func TestStateFile(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	file := filepath.Join(t.TempDir(), "state", "markets.json")
	c := &clock{t: sessionEnd.Add(time.Hour)}
	r := Request{Symbols: syms("AAPL"), PauseWhenClosed: true}
	newMarkets(f, c, file).State(context.Background(), r)
	c.Add(time.Minute)
	st, _ := newMarkets(f, c, file).State(context.Background(), r)
	if q := st.Quotes["AAPL"]; q == nil || q.Price != 110 {
		t.Errorf("restored %+v", q)
	}
	if a := f.hit("/chart/AAPL"); a != 1 {
		t.Errorf("AAPL fetched %d times, want once (the second from the file)", a)
	}
}

func TestSearch(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	l := newMarkets(f, &clock{t: sessionStart}, "").Lookup()
	res, err := l.Search(context.Background(), SearchRequest{Query: "a"})
	if err != nil {
		t.Fatal(err)
	}
	got, _ := json.Marshal(res.Matches)
	want := `[{"symbol":"AAPL","display":"AAPL","name":"Apple Inc.","kind":"equity","exchange":"NASDAQ","source":"yahoo"},` +
		`{"symbol":"bitcoin","display":"BTC","name":"Bitcoin","kind":"crypto","exchange":"CoinGecko #1","source":"coingecko"},` +
		`{"symbol":"x","display":"X","name":"X","kind":"crypto","exchange":"CoinGecko","source":"coingecko"}]`
	if string(got) != want {
		t.Errorf("matches\n got %s\nwant %s", got, want)
	}
	if res, _ := l.Search(context.Background(), SearchRequest{Query: "  "}); len(res.Matches) != 0 {
		t.Error("matches for an empty query")
	}
}

func TestHistory(t *testing.T) {
	t.Parallel()
	f := newFake(t)
	c := &clock{t: sessionStart}
	l := newMarkets(f, c, "").Lookup()
	h, err := l.History(context.Background(), HistoryRequest{Symbol: "bitcoin", Source: SourceCoinGecko, Range: "5d"})
	if err != nil {
		t.Fatal(err)
	}
	if len(h.Points) != 3 || h.Points[0][0] != 1000 || h.High != 9 || h.Low != 5 || h.Reference != 5 || h.Currency != "USD" {
		t.Errorf("history %+v", h)
	}
	h, _ = l.History(context.Background(), HistoryRequest{Symbol: "AAPL", Range: "1d"})
	if h.Reference != 100 || h.Start != sessionStart.Unix() {
		t.Errorf("a day's reference %v start %v, want the previous close and the session", h.Reference, h.Start)
	}
	l.History(context.Background(), HistoryRequest{Symbol: "AAPL", Range: "1d"})
	if n := f.hit("/chart/AAPL"); n != 1 {
		t.Errorf("fetched %d times, want once (cached)", n)
	}
	if _, err := l.History(context.Background(), HistoryRequest{Symbol: "AAPL", Range: "2w"}); err == nil {
		t.Error("no error for an unknown range")
	}
}
