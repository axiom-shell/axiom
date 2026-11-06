package markets

import (
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func list(t *testing.T, text string) *jsonx.Array {
	t.Helper()
	v, err := jsonx.Unmarshal([]byte(text))
	if err != nil {
		t.Fatal(err)
	}
	return v.(*jsonx.Array)
}

const sample = `[{"id": "aapl", "symbol": "AAPL", "source": "yahoo", "label": "", "quantity": 10},
	{"id": "btc", "symbol": "BTC-USD", "label": "Bitcoin"},
	{"id": "btc2", "symbol": "bitcoin", "source": "coingecko", "label": "Bitcoin"},
	{"id": "eth", "symbol": "ETH-USD", "label": "Ether"},
	{"id": "doge", "symbol": "DOGE-USD", "label": "Meme"},
	{"id": "pepe", "symbol": "pepe", "source": "coingecko", "label": "Meme"}]`

func TestFind(t *testing.T) {
	t.Parallel()
	l := list(t, sample)
	for _, tc := range []struct {
		ref, id string
		kind    axerr.Kind
	}{
		{"aapl", "aapl", ""},
		{"AAPL", "aapl", ""},
		{"btc-usd", "btc", ""},
		{"btc2", "btc2", ""},
		{"ether", "eth", ""},
		{"Bitcoin", "btc2", ""},        // a symbol before a label
		{"meme", "", axerr.BadRequest}, // two labels
		{"TSLA", "", axerr.NotFound},
		{" ", "", axerr.BadRequest},
	} {
		item, err := Find(l, tc.ref)
		if tc.kind != "" {
			if axerr.KindOf(err) != tc.kind {
				t.Errorf("%q: %v, want %s", tc.ref, err, tc.kind)
			}
			continue
		}
		if err != nil || item.Value("id") != tc.id {
			t.Errorf("%q: %v %v, want %s", tc.ref, item, err, tc.id)
		}
	}
}

func TestHasAndFreeID(t *testing.T) {
	t.Parallel()
	l := list(t, sample)
	if !Has(l, "aapl", "") || !Has(l, "bitcoin", SourceCoinGecko) || Has(l, "bitcoin", SourceYahoo) {
		t.Error("Has")
	}
	for symbol, want := range map[string]string{"AAPL": "aapl2", "^GSPC": "gspc", "BTC-USD": "btcusd", "^^": "symbol", "btc": "btc3"} {
		if got := FreeID(l, symbol); got != want {
			t.Errorf("FreeID(%q) = %q, want %q", symbol, got, want)
		}
	}
}

func TestAmount(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		text    string
		current float64
		want    float64
		ok      bool
	}{
		{"12", 5, 12, true},
		{"+2", 5, 7, true},
		{"-0.5", 5, 4.5, true},
		{"0", 5, 0, true},
		{"-6", 5, 0, false},
		{"lots", 5, 0, false},
		{"NaN", 5, 0, false},
		{"+0.01", 0.05, 0.06, true},
		{"-0.02", 0.06, 0.04, true},
	} {
		got, err := Amount(tc.text, tc.current)
		if (err == nil) != tc.ok || got != tc.want {
			t.Errorf("Amount(%q, %v) = %v, %v", tc.text, tc.current, got, err)
		}
	}
}

func TestRequestFor(t *testing.T) {
	t.Parallel()
	r := RequestFor(list(t, sample), "EUR", true)
	if len(r.Symbols) != 6 || r.Symbols[2] != (Symbol{"bitcoin", SourceCoinGecko}) || r.Symbols[0].Source != SourceYahoo || !r.Convert || r.BaseCurrency != "EUR" || !r.PauseWhenClosed {
		t.Errorf("request %+v", r)
	}
	if RequestFor(list(t, `[{"id": "x", "symbol": "X"}]`), "USD", false).Convert {
		t.Error("rates asked with no holding")
	}
}
