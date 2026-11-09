package filesearch

import "math"

// Use is a file's use record, as Utils.recordUse keeps an app's: how
// often it was opened from the launcher, and when last (ms).
type Use struct {
	Count int   `json:"count"`
	Last  int64 `json:"last"`
}

// Frecency is a use record's weight at now (ms): its count, faded with
// age, as Search.frecency weighs an app's.
func Frecency(u Use, now int64) float64 {
	if u.Count <= 0 {
		return 0
	}
	days := float64(now-u.Last) / 86400000
	fade := 0.25
	switch {
	case days < 1:
		fade = 1
	case days < 7:
		fade = 0.7
	case days < 30:
		fade = 0.5
	}
	return float64(u.Count) * fade
}

// UseBonus is the ranking bonus for a frecency: up to 25, growing with
// its log, as Search.useBonus.
func UseBonus(frecency float64) float64 {
	return math.Min(25, 8*math.Log2(1+frecency))
}
