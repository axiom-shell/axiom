package cli

import (
	"encoding/json"
	"strings"
	"testing"
)

// Offline, `axiom markets` edits the watchlist in the file: add, hold
// (absolute and relative), alerts, moves and removal, and list reads it
// back.
func TestMarketsOffline(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	mk := func(args ...string) (int, string, string) {
		return run(t, Root(), append([]string{"--offline", "--config-dir", dir, "markets"}, args...)...)
	}
	steps := []struct {
		args []string
		ok   bool
		out  string
	}{
		{[]string{"add", "TSLA", "--hold", "3"}, true, "Added TSLA (id tsla)\n"},
		{[]string{"add", "tsla"}, false, ""},
		{[]string{"add", "--coingecko", "--label", "PEPE", "pepe"}, true, "Added pepe (id pepe)\n"},
		{[]string{"hold", "tsla", "+2", "--cost", "180"}, true, "TSLA: 5 held at 180 each\n"},
		{[]string{"hold", "TSLA", "-1.5"}, true, "TSLA: 3.5 held\n"},
		{[]string{"hold", "TSLA", "-10"}, false, ""},
		{[]string{"hold", "aapl", "4"}, true, "AAPL: 4 held\n"},
		{[]string{"hold", "nope", "4"}, false, ""},
		{[]string{"alert", "pepe", "--above", "0.00001"}, true, "PEPE: alerts above 0.00001\n"},
		{[]string{"alert", "pepe"}, false, ""},
		{[]string{"alert", "pepe", "--clear"}, true, "PEPE: no alerts\n"},
		{[]string{"move", "tsla", "1"}, true, "Moved TSLA to 1\n"},
		{[]string{"remove", "Bitcoin"}, true, "Removed Bitcoin\n"},
	}
	for _, s := range steps {
		code, out, errOut := mk(s.args...)
		if (code == 0) != s.ok {
			t.Fatalf("%v: exit %d (%s%s)", s.args, code, out, errOut)
		}
		if s.ok && out != s.out {
			t.Errorf("%v printed %q, want %q", s.args, out, s.out)
		}
	}
	code, out, errOut := mk("--json", "list")
	if code != 0 {
		t.Fatalf("list: %d %s", code, errOut)
	}
	var got struct {
		Items []struct {
			Item struct {
				ID          string  `json:"id"`
				Quantity    float64 `json:"quantity"`
				AverageCost float64 `json:"averageCost"`
				AlertAbove  float64 `json:"alertAbove"`
			} `json:"item"`
			Quote any `json:"quote"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(out), &got); err != nil {
		t.Fatalf("list --json: %v: %s", err, out)
	}
	var ids []string
	for _, it := range got.Items {
		ids = append(ids, it.Item.ID)
		if it.Quote != nil {
			t.Errorf("a quote offline: %v", it.Quote)
		}
	}
	// The defaults (sp500, aapl, btc, eth) with TSLA first, Bitcoin gone
	if strings.Join(ids, " ") != "tsla sp500 aapl eth pepe" {
		t.Errorf("order %v", ids)
	}
	if tsla := got.Items[0].Item; tsla.Quantity != 3.5 || tsla.AverageCost != 180 {
		t.Errorf("tsla %+v", tsla)
	}
	if got.Items[4].Item.AlertAbove != 0 {
		t.Error("alert not cleared")
	}
	if _, out, _ := mk("list"); !strings.Contains(out, "TSLA") || !strings.Contains(out, "3.5") {
		t.Errorf("list text:\n%s", out)
	}
}
