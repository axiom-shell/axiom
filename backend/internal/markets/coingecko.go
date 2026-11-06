package markets

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// fetchGecko fetches every CoinGecko coin in one call, priced in base.
func (m *Markets) fetchGecko(ctx context.Context, syms []Symbol, base string, now time.Time) error {
	ids := make([]string, len(syms))
	for i, s := range syms {
		ids[i] = s.Symbol
	}
	var reply []struct {
		ID          string  `json:"id"`
		Symbol      string  `json:"symbol"`
		Name        string  `json:"name"`
		Price       float64 `json:"current_price"`
		Change      float64 `json:"price_change_24h"`
		Percent     float64 `json:"price_change_percentage_24h"`
		High        float64 `json:"high_24h"`
		Low         float64 `json:"low_24h"`
		LastUpdated string  `json:"last_updated"`
		Sparkline   *struct {
			Price []float64 `json:"price"`
		} `json:"sparkline_in_7d"`
	}
	q := url.Values{"ids": {strings.Join(ids, ",")}, "vs_currency": {strings.ToLower(base)}, "sparkline": {"true"}}
	err := m.get(ctx, m.o.CoinGeckoMarket+"?"+q.Encode(), &reply)
	if err != nil {
		for _, s := range syms {
			m.keep(Key(s), nil, err, s)
		}
		return err
	}
	found := map[string]bool{}
	for _, c := range reply {
		found[c.ID] = true
		end := now
		if t, err := time.Parse(time.RFC3339, c.LastUpdated); err == nil {
			end = t
		}
		qt := &Quote{
			Symbol:        c.ID,
			Source:        SourceCoinGecko,
			Name:          firstOf(c.Name, c.ID),
			Kind:          "crypto",
			Currency:      base,
			Exchange:      "CoinGecko",
			Price:         c.Price,
			PrevClose:     c.Price - c.Change,
			Change:        c.Change,
			ChangePercent: c.Percent,
			DayHigh:       c.High,
			DayLow:        c.Low,
			SessionStart:  end.Add(-24 * time.Hour).Unix(),
			SessionEnd:    end.Unix(),
			Points:        [][2]float64{},
			UpdatedAt:     now.UnixMilli(),
		}
		// The 7-day sparkline is hourly, ending now: its last day
		if c.Sparkline != nil {
			p := c.Sparkline.Price
			p = p[max(0, len(p)-25):]
			for i, v := range p {
				t := end.Add(-time.Duration(len(p)-1-i) * time.Hour)
				qt.Points = append(qt.Points, [2]float64{float64(t.Unix()), v})
			}
		}
		m.keep(Key(Symbol{c.ID, SourceCoinGecko}), qt, nil, Symbol{c.ID, SourceCoinGecko})
	}
	for _, s := range syms {
		if !found[s.Symbol] {
			m.keep(Key(s), nil, fmt.Errorf("%s: %w", s.Symbol, errNotFound), s)
		}
	}
	return nil
}

// The days CoinGecko's chart covers for each history range.
var geckoDays = map[string]string{"1d": "1", "5d": "5", "1mo": "30", "6mo": "180", "1y": "365"}

// geckoHistory is coin id's chart over rng, priced in base.
func (m *Markets) geckoHistory(ctx context.Context, id, base, rng string) (*History, error) {
	var reply struct {
		Prices [][2]float64 `json:"prices"`
	}
	q := url.Values{"vs_currency": {strings.ToLower(base)}, "days": {geckoDays[rng]}}
	if err := m.get(ctx, m.o.CoinGeckoChart+url.PathEscape(id)+"/market_chart?"+q.Encode(), &reply); err != nil {
		return nil, err
	}
	h := &History{Points: make([][2]float64, 0, len(reply.Prices)), Currency: strings.ToUpper(base)}
	for _, p := range reply.Prices {
		h.Points = append(h.Points, [2]float64{p[0] / 1000, p[1]})
	}
	return h.finish(), nil
}

// geckoSearch is CoinGecko's coins matching query.
func (m *Markets) geckoSearch(ctx context.Context, query string) ([]Match, error) {
	var reply struct {
		Coins []struct {
			ID     string `json:"id"`
			Symbol string `json:"symbol"`
			Name   string `json:"name"`
			Rank   *int   `json:"market_cap_rank"`
		} `json:"coins"`
	}
	if err := m.get(ctx, m.o.CoinGeckoSearch+"?"+url.Values{"query": {query}}.Encode(), &reply); err != nil {
		return nil, err
	}
	out := []Match{}
	for _, c := range reply.Coins[:min(4, len(reply.Coins))] {
		ex := "CoinGecko"
		if c.Rank != nil {
			ex = "CoinGecko #" + strconv.Itoa(*c.Rank)
		}
		out = append(out, Match{Symbol: c.ID, Display: strings.ToUpper(c.Symbol), Name: c.Name, Kind: "crypto", Exchange: ex, Source: SourceCoinGecko})
	}
	return out, nil
}
