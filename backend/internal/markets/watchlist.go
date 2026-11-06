package markets

import (
	"strconv"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The watchlist is the config's Markets.symbols, read as the config tree
// (`axiom markets`): items { id, symbol, source, label, quantity,
// averageCost, alertAbove, alertBelow }.

// Find is the watchlist item ref names: its id, else its symbol, else its
// label, any case. None or several is an error naming them.
func Find(list *jsonx.Array, ref string) (*jsonx.Object, error) {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return nil, axerr.New(axerr.BadRequest, "no symbol given")
	}
	for _, key := range []string{"id", "symbol", "label"} {
		var found []*jsonx.Object
		for _, v := range items(list) {
			if s, _ := v.Value(key).(string); s != "" && strings.EqualFold(s, ref) {
				found = append(found, v)
			}
		}
		if len(found) == 1 {
			return found[0], nil
		}
		if len(found) > 1 {
			ids := make([]string, len(found))
			for i, f := range found {
				ids[i] = str(f.Value("id"))
			}
			return nil, axerr.New(axerr.BadRequest, "%q is several watchlist items (%s): name one by its id", ref, strings.Join(ids, ", "))
		}
	}
	return nil, axerr.New(axerr.NotFound, "%q isn't on the watchlist (axiom markets list)", ref)
}

// Has: whether the watchlist already watches symbol from source.
func Has(list *jsonx.Array, symbol, source string) bool {
	for _, v := range items(list) {
		if strings.EqualFold(str(v.Value("symbol")), symbol) && sourceOf(v) == normalSource(source) {
			return true
		}
	}
	return false
}

// FreeID is an id for a new item watching symbol: its letters and
// digits, lower case ("^GSPC" → "gspc"), numbered past those taken.
func FreeID(list *jsonx.Array, symbol string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(symbol) {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	base := b.String()
	if base == "" {
		base = "symbol"
	}
	taken := map[string]bool{}
	for _, v := range items(list) {
		taken[str(v.Value("id"))] = true
	}
	id := base
	for n := 2; taken[id]; n++ {
		id = base + strconv.Itoa(n)
	}
	return id
}

// Amount reads an amount typed against current: "12" is 12, "+2" and
// "-0.5" add to current. A result below 0 is an error.
func Amount(text string, current float64) (float64, error) {
	t := strings.TrimSpace(text)
	relative := strings.HasPrefix(t, "+") || strings.HasPrefix(t, "-")
	v, err := strconv.ParseFloat(t, 64)
	if err != nil || v != v {
		return 0, axerr.New(axerr.BadRequest, "%q isn't a number (12, +2 or -0.5)", text)
	}
	if relative {
		// 12 significant digits: 0.05 + 0.01 is 0.06, not 0.060000000000000005
		v, _ = strconv.ParseFloat(strconv.FormatFloat(v+current, 'g', 12, 64), 64)
	}
	if v < 0 {
		return 0, axerr.New(axerr.BadRequest, "that leaves %v: an amount can't go below 0", v)
	}
	return v, nil
}

// RequestFor is the topic's request for the watchlist, as MarketsManager
// sends it (MarketMath.request).
func RequestFor(list *jsonx.Array, baseCurrency string, pauseWhenClosed bool) Request {
	r := Request{Symbols: []Symbol{}, BaseCurrency: baseCurrency, PauseWhenClosed: pauseWhenClosed}
	for _, v := range items(list) {
		symbol := strings.TrimSpace(str(v.Value("symbol")))
		if symbol == "" {
			continue
		}
		r.Symbols = append(r.Symbols, Symbol{Symbol: symbol, Source: sourceOf(v)})
		if Num(v.Value("quantity")) > 0 {
			r.Convert = true
		}
	}
	return r
}

// ItemKey is an item's key in State.Quotes.
func ItemKey(item *jsonx.Object) string {
	return Key(Symbol{Symbol: strings.TrimSpace(str(item.Value("symbol"))), Source: sourceOf(item)})
}

func items(list *jsonx.Array) []*jsonx.Object {
	if list == nil {
		return nil
	}
	out := make([]*jsonx.Object, 0, list.Len())
	for _, v := range list.Items {
		if o, ok := v.(*jsonx.Object); ok {
			out = append(out, o)
		}
	}
	return out
}

func sourceOf(item *jsonx.Object) string {
	return normalSource(str(item.Value("source")))
}

func normalSource(s string) string {
	if s == SourceCoinGecko {
		return SourceCoinGecko
	}
	return SourceYahoo
}

// Num is a config number, 0 for anything else.
func Num(v any) float64 {
	f, ok := v.(float64)
	if !ok || f != f {
		return 0
	}
	return f
}

func str(v any) string {
	s, _ := v.(string)
	return s
}
