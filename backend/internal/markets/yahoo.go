package markets

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"strings"
	"sync"
	"time"
)

// chartReply is the part of Yahoo's chart answer read here.
type chartReply struct {
	Chart struct {
		Result []struct {
			Meta struct {
				Currency           string  `json:"currency"`
				Symbol             string  `json:"symbol"`
				ExchangeName       string  `json:"exchangeName"`
				FullExchangeName   string  `json:"fullExchangeName"`
				InstrumentType     string  `json:"instrumentType"`
				RegularMarketPrice float64 `json:"regularMarketPrice"`
				RegularMarketTime  int64   `json:"regularMarketTime"`
				DayHigh            float64 `json:"regularMarketDayHigh"`
				DayLow             float64 `json:"regularMarketDayLow"`
				ChartPreviousClose float64 `json:"chartPreviousClose"`
				PreviousClose      float64 `json:"previousClose"`
				LongName           string  `json:"longName"`
				ShortName          string  `json:"shortName"`
				Period             struct {
					Pre, Regular, Post period
				} `json:"currentTradingPeriod"`
				// The chart's own sessions, oldest first ([[{start, end}]]
				// for a day): after a close, the current period may already
				// be the next session's
				TradingPeriods json.RawMessage `json:"tradingPeriods"`
			} `json:"meta"`
			Timestamp  []int64 `json:"timestamp"`
			Indicators struct {
				Quote []struct {
					Close []*float64 `json:"close"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
		Error *struct {
			Code        string `json:"code"`
			Description string `json:"description"`
		} `json:"error"`
	} `json:"chart"`
}

type period struct {
	Start int64 `json:"start"`
	End   int64 `json:"end"`
}

// lastPeriod is the last session in a chart's tradingPeriods (a day's
// [[{start, end}]]), or ok false when it holds none.
func lastPeriod(raw json.RawMessage) (period, bool) {
	var days [][]period
	if json.Unmarshal(raw, &days) != nil || len(days) == 0 || len(days[len(days)-1]) == 0 {
		return period{}, false
	}
	day := days[len(days)-1]
	return period{day[0].Start, day[len(day)-1].End}, day[0].Start > 0
}

// The chart's interval for each history range.
var yahooIntervals = map[string]string{"1d": "5m", "5d": "30m", "1mo": "1h", "6mo": "1d", "1y": "1d"}

// chart fetches symbol's chart over rng, every interval.
func (m *Markets) chart(ctx context.Context, symbol, rng, interval string) (*chartReply, error) {
	q := url.Values{"range": {rng}, "interval": {interval}, "includePrePost": {"false"}}
	var reply chartReply
	err := m.get(ctx, m.o.YahooChart+url.PathEscape(symbol)+"?"+q.Encode(), &reply)
	if errors.Is(err, errNotFound) {
		return nil, fmt.Errorf("%s: %w", symbol, err)
	}
	if err != nil {
		return nil, err
	}
	if e := reply.Chart.Error; e != nil {
		return nil, fmt.Errorf("%s: %s", symbol, e.Description)
	}
	if len(reply.Chart.Result) == 0 {
		return nil, fmt.Errorf("%s: %w", symbol, errNotFound)
	}
	return &reply, nil
}

// yahooQuote fetches symbol's day: its last session, or for crypto
// (which never closes, and whose Yahoo day is the UTC one) the last 24
// hours, as CoinGecko's.
func (m *Markets) yahooQuote(ctx context.Context, symbol string, crypto bool) (*Quote, error) {
	rng, interval := "1d", "5m"
	if crypto {
		rng, interval = "5d", "15m"
	}
	reply, err := m.chart(ctx, symbol, rng, interval)
	if err != nil {
		return nil, err
	}
	r := reply.Chart.Result[0]
	meta := r.Meta
	q := &Quote{
		Symbol:       symbol,
		Source:       SourceYahoo,
		Name:         firstOf(meta.LongName, meta.ShortName, symbol),
		Kind:         yahooKind(meta.InstrumentType),
		Currency:     meta.Currency,
		Exchange:     firstOf(meta.FullExchangeName, meta.ExchangeName),
		Price:        meta.RegularMarketPrice,
		PrevClose:    firstNonZero(meta.ChartPreviousClose, meta.PreviousClose),
		DayHigh:      meta.DayHigh,
		DayLow:       meta.DayLow,
		SessionStart: meta.Period.Regular.Start,
		SessionEnd:   meta.Period.Regular.End,
		OpenAt:       meta.Period.Regular.Start,
		CloseAt:      meta.Period.Regular.End,
		PreStart:     meta.Period.Pre.Start,
		PostEnd:      meta.Period.Post.End,
		Points:       points(r.Timestamp, r.Indicators.Quote),
		UpdatedAt:    m.o.Now().UnixMilli(),
	}
	if p, ok := lastPeriod(meta.TradingPeriods); ok && !crypto {
		q.SessionStart, q.SessionEnd = p.Start, p.End
	}
	if q.Kind == "crypto" && crypto {
		rolling(q, m.o.Now())
	}
	if q.PrevClose != 0 {
		q.Change = q.Price - q.PrevClose
		q.ChangePercent = q.Change / q.PrevClose * 100
	}
	return q, nil
}

// rolling makes q's day the last 24 hours: its points, range and the
// price a day ago as the previous close.
func rolling(q *Quote, now time.Time) {
	from := now.Add(-24 * time.Hour).Unix()
	var day [][2]float64
	for _, p := range q.Points {
		if int64(p[0]) >= from {
			day = append(day, p)
		} else {
			// The last point before the window starts it, so the line
			// reaches its left edge
			day = [][2]float64{p}
		}
	}
	q.Points = append([][2]float64{}, day...)
	q.SessionStart, q.SessionEnd, q.OpenAt, q.CloseAt = from, now.Unix(), 0, 0
	if len(day) > 0 {
		q.PrevClose = day[0][1]
		q.DayHigh, q.DayLow = day[0][1], day[0][1]
		for _, p := range day {
			q.DayHigh, q.DayLow = max(q.DayHigh, p[1]), min(q.DayLow, p[1])
		}
		q.DayHigh, q.DayLow = max(q.DayHigh, q.Price), min(q.DayLow, q.Price)
	}
}

func points(ts []int64, quotes []struct {
	Close []*float64 `json:"close"`
}) [][2]float64 {
	out := [][2]float64{}
	if len(quotes) == 0 {
		return out
	}
	closes := quotes[0].Close
	for i, t := range ts {
		if i < len(closes) && closes[i] != nil && !math.IsNaN(*closes[i]) {
			out = append(out, [2]float64{float64(t), *closes[i]})
		}
	}
	return out
}

// fetchYahoo fetches syms, a few at once, into the cache.
func (m *Markets) fetchYahoo(ctx context.Context, syms []Symbol) []error {
	type result struct {
		s   Symbol
		q   *Quote
		err error
	}
	results := make([]result, len(syms))
	var wg sync.WaitGroup
	sem := make(chan struct{}, workers)
	for i, s := range syms {
		// Crypto's day is the last 24 hours: known from its last quote,
		// else from the first answer, asked again
		crypto := m.cache[Key(s)] != nil && m.cache[Key(s)].Kind == "crypto"
		wg.Add(1)
		go func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			q, err := m.yahooQuote(ctx, s.Symbol, crypto)
			if err == nil && !crypto && q.Kind == "crypto" {
				q, err = m.yahooQuote(ctx, s.Symbol, true)
			}
			results[i] = result{s, q, err}
		}()
	}
	wg.Wait()
	var errs []error
	for _, r := range results {
		m.keep(Key(r.s), r.q, r.err, r.s)
		if r.err != nil {
			errs = append(errs, r.err)
		}
	}
	return errs
}

// convert fills st.FX: each quote currency's rate to base, from Yahoo's
// "<CUR><BASE>=X" pair (cached like any quote). Subunit currencies
// (GBp, ZAc, ILA) are their unit's rate over 100.
func (m *Markets) convert(ctx context.Context, st *State, base string, now time.Time) []error {
	var errs []error
	for _, q := range st.Quotes {
		cur := q.Currency
		if cur == "" || cur == base {
			continue
		}
		if _, ok := st.FX[cur]; ok {
			continue
		}
		unit, scale := strings.ToUpper(cur), 1.0
		if sub, ok := subunits[cur]; ok {
			unit, scale = sub, 100
		}
		if unit == base {
			st.FX[cur] = 1 / scale
			continue
		}
		pair := unit + base + "=X"
		fq := m.fx[pair]
		if fq == nil || fq.Stale || now.Sub(time.UnixMilli(fq.UpdatedAt)) >= closedRecheck/4 {
			nq, err := m.yahooQuote(ctx, pair, false)
			if err != nil {
				errs = append(errs, err)
				if fq != nil {
					fq.Stale = true
				}
			} else {
				fq = nq
				m.fx[pair] = nq
			}
		}
		if fq != nil && fq.Price > 0 {
			st.FX[cur] = fq.Price / scale
		}
	}
	return errs
}

var subunits = map[string]string{"GBp": "GBP", "GBX": "GBP", "ZAc": "ZAR", "ILA": "ILS"}

func yahooKind(t string) string {
	switch strings.ToUpper(t) {
	case "EQUITY":
		return "equity"
	case "ETF":
		return "etf"
	case "INDEX":
		return "index"
	case "CRYPTOCURRENCY":
		return "crypto"
	case "CURRENCY":
		return "fx"
	case "FUTURE":
		return "future"
	case "MUTUALFUND":
		return "fund"
	}
	return "other"
}

// yahooHistory is symbol's chart over rng.
func (m *Markets) yahooHistory(ctx context.Context, symbol, rng string) (*History, error) {
	reply, err := m.chart(ctx, symbol, rng, yahooIntervals[rng])
	if err != nil {
		return nil, err
	}
	r := reply.Chart.Result[0]
	h := &History{Points: points(r.Timestamp, r.Indicators.Quote), Currency: r.Meta.Currency}
	if rng == "1d" {
		h.Reference = firstNonZero(r.Meta.ChartPreviousClose, r.Meta.PreviousClose)
		h.Start, h.End = r.Meta.Period.Regular.Start, r.Meta.Period.Regular.End
		if p, ok := lastPeriod(r.Meta.TradingPeriods); ok {
			h.Start, h.End = p.Start, p.End
		}
	}
	return h.finish(), nil
}

// yahooSearch is Yahoo's matches for query.
func (m *Markets) yahooSearch(ctx context.Context, query string) ([]Match, error) {
	var reply struct {
		Quotes []struct {
			Symbol    string `json:"symbol"`
			ShortName string `json:"shortname"`
			LongName  string `json:"longname"`
			QuoteType string `json:"quoteType"`
			Exchange  string `json:"exchDisp"`
		} `json:"quotes"`
	}
	q := url.Values{"q": {query}, "quotesCount": {"8"}, "newsCount": {"0"}, "listsCount": {"0"}}
	if err := m.get(ctx, m.o.YahooSearch+"?"+q.Encode(), &reply); err != nil {
		return nil, err
	}
	out := []Match{}
	for _, r := range reply.Quotes {
		if r.Symbol == "" {
			continue
		}
		out = append(out, Match{Symbol: r.Symbol, Display: r.Symbol, Name: firstOf(r.LongName, r.ShortName, r.Symbol), Kind: yahooKind(r.QuoteType), Exchange: r.Exchange, Source: SourceYahoo})
	}
	return out, nil
}

func firstOf(s ...string) string {
	for _, v := range s {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}

func firstNonZero(f ...float64) float64 {
	for _, v := range f {
		if v != 0 {
			return v
		}
	}
	return 0
}
