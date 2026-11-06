package markets

import (
	"context"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// History is a symbol's chart over a range (`markets.history`).
type History struct {
	// [unix seconds, price], oldest first
	Points [][2]float64 `json:"points"`
	// The line the chart is read against: the previous close for a day,
	// else the range's first price
	Reference float64 `json:"reference"`
	High      float64 `json:"high"`
	Low       float64 `json:"low"`
	Currency  string  `json:"currency"`
	// The time axis (unix seconds); 0: the points' own
	Start int64 `json:"start"`
	End   int64 `json:"end"`
}

func (h *History) finish() *History {
	for i, p := range h.Points {
		if i == 0 || p[1] > h.High {
			h.High = p[1]
		}
		if i == 0 || p[1] < h.Low {
			h.Low = p[1]
		}
	}
	if h.Reference == 0 && len(h.Points) > 0 {
		h.Reference = h.Points[0][1]
	}
	return h
}

// HistoryRequest asks for a symbol's chart.
type HistoryRequest struct {
	Symbol       string `json:"symbol"`
	Source       string `json:"source"`
	Range        string `json:"range"` // 1d, 5d, 1mo, 6mo, 1y
	BaseCurrency string `json:"baseCurrency"`
}

// Match is a symbol found by a search.
type Match struct {
	// What to watch: Yahoo's symbol or CoinGecko's coin id
	Symbol string `json:"symbol"`
	// What to show for it ("BTC" for "bitcoin")
	Display  string `json:"display"`
	Name     string `json:"name"`
	Kind     string `json:"kind"`
	Exchange string `json:"exchange"`
	Source   string `json:"source"`
}

// SearchRequest is what was typed.
type SearchRequest struct {
	Query string `json:"query"`
}

// SearchResult is Yahoo's matches, then CoinGecko's coins; Error says
// why one of them has none.
type SearchResult struct {
	Matches []Match `json:"matches"`
	Error   string  `json:"error"`
}

// Lookup answers the search and the history; it shares a Markets' hosts'
// backoff but not its lock, so a slow fetch doesn't hold up a search.
type Lookup struct {
	m       *Markets
	mu      sync.Mutex
	history map[HistoryRequest]cachedHistory
}

type cachedHistory struct {
	h  *History
	at time.Time
}

// A range's chart is fetched again after this
var historyTTL = map[string]time.Duration{"1d": 2 * time.Minute, "5d": 10 * time.Minute, "1mo": time.Hour, "6mo": 6 * time.Hour, "1y": 6 * time.Hour}

// Lookup is m's search and history.
func (m *Markets) Lookup() *Lookup {
	return &Lookup{m: m, history: map[HistoryRequest]cachedHistory{}}
}

// History is r's chart, cached for its range's TTL.
func (l *Lookup) History(ctx context.Context, r HistoryRequest) (*History, error) {
	ttl, ok := historyTTL[r.Range]
	if !ok {
		return nil, axerr.New(axerr.BadRequest, "unknown range %q", r.Range)
	}
	if strings.TrimSpace(r.Symbol) == "" {
		return nil, axerr.New(axerr.BadRequest, "no symbol")
	}
	if r.BaseCurrency == "" {
		r.BaseCurrency = "USD"
	}
	now := l.m.o.Now()
	l.mu.Lock()
	c, hit := l.history[r]
	l.mu.Unlock()
	if hit && now.Sub(c.at) < ttl {
		return c.h, nil
	}
	var h *History
	var err error
	if r.Source == SourceCoinGecko {
		h, err = l.m.geckoHistory(ctx, r.Symbol, r.BaseCurrency, r.Range)
	} else {
		h, err = l.m.yahooHistory(ctx, r.Symbol, r.Range)
	}
	if err != nil {
		if hit {
			return c.h, nil
		}
		return nil, axerr.Wrap(axerr.Unavailable, err, "fetching the chart")
	}
	l.mu.Lock()
	if len(l.history) > 64 {
		clear(l.history)
	}
	l.history[r] = cachedHistory{h, now}
	l.mu.Unlock()
	return h, nil
}

// Search is the symbols matching r's query, from both sources at once.
func (l *Lookup) Search(ctx context.Context, r SearchRequest) (SearchResult, error) {
	q := strings.TrimSpace(r.Query)
	if q == "" {
		return SearchResult{Matches: []Match{}}, nil
	}
	var yahoo, gecko []Match
	var yerr, gerr error
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); yahoo, yerr = l.m.yahooSearch(ctx, q) }()
	go func() { defer wg.Done(); gecko, gerr = l.m.geckoSearch(ctx, q) }()
	wg.Wait()
	res := SearchResult{Matches: append(yahoo, gecko...)}
	if res.Matches == nil {
		res.Matches = []Match{}
	}
	if err := errors.Join(yerr, gerr); err != nil {
		if len(res.Matches) == 0 {
			return res, axerr.Wrap(axerr.Unavailable, err, "searching symbols")
		}
		res.Error = err.Error()
	}
	return res, nil
}
