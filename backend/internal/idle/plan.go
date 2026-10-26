package idle

import (
	"slices"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Settings are the Idle section, as the service reads it.
type Settings struct {
	Enabled            bool
	DimTimeout         time.Duration
	DimMode            string // "to" | "by"
	DimLevel, DimBy    int    // percent
	LockTimeout        time.Duration
	ScreenOffTimeout   time.Duration
	SuspendTimeout     time.Duration
	LockBeforeSleep    bool
	ScreenOnAfterSleep bool
	RespectInhibitors  bool
	Items              []Item
}

// Item is one of the user's own listeners (Idle.items).
type Item struct {
	Timeout   time.Duration
	OnTimeout string
	OnResume  string
	Enabled   bool
}

// SettingsFrom reads the Idle section of a loaded config (its defaults
// filled: nothing here stands in for one).
// reads: Idle.*
func SettingsFrom(section *jsonx.Object) Settings {
	if section == nil {
		return Settings{}
	}
	ms := func(v any) time.Duration { return time.Duration(jsonx.ToNumber(v)) * time.Millisecond }
	// Only a string: JS's String() would make a missing command "undefined"
	str := func(v any) string { s, _ := v.(string); return s }
	sub := func(key string) *jsonx.Object {
		o, _ := section.Value(key).(*jsonx.Object)
		if o == nil {
			o = &jsonx.Object{}
		}
		return o
	}
	dim := sub("dim")
	s := Settings{
		Enabled:            jsonx.Truthy(section.Value("enabled")),
		DimTimeout:         ms(dim.Value("timeout")),
		DimMode:            str(dim.Value("mode")),
		DimLevel:           int(jsonx.ToNumber(dim.Value("level"))),
		DimBy:              int(jsonx.ToNumber(dim.Value("by"))),
		LockTimeout:        ms(sub("lock").Value("timeout")),
		ScreenOffTimeout:   ms(sub("screenOff").Value("timeout")),
		SuspendTimeout:     ms(sub("suspend").Value("timeout")),
		LockBeforeSleep:    jsonx.Truthy(section.Value("lockBeforeSleep")),
		ScreenOnAfterSleep: jsonx.Truthy(section.Value("screenOnAfterSleep")),
		RespectInhibitors:  jsonx.Truthy(section.Value("respectInhibitors")),
	}
	if items, ok := section.Value("items").(*jsonx.Array); ok {
		for _, v := range items.Items {
			o, ok := v.(*jsonx.Object)
			if !ok {
				continue
			}
			s.Items = append(s.Items, Item{
				Timeout:   ms(o.Value("timeout")),
				OnTimeout: str(o.Value("onTimeout")),
				OnResume:  str(o.Value("onResume")),
				Enabled:   jsonx.Truthy(o.Value("enabled")),
			})
		}
	}
	return s
}

// Kind is what an action does.
type Kind string

// The actions
const (
	None      Kind = ""
	Dim       Kind = "dim"   // Mode, Percent
	Undim     Kind = "undim" //
	Lock      Kind = "lock"
	ScreenOff Kind = "screenOff"
	ScreenOn  Kind = "screenOn"
	Suspend   Kind = "suspend"
	Command   Kind = "command" // Line, through sh -c
)

// Action is one thing a listener does.
type Action struct {
	Kind    Kind   `json:"kind"`
	Mode    string `json:"mode,omitempty"`    // Dim: "to" | "by"
	Percent int    `json:"percent,omitempty"` // Dim
	Line    string `json:"line,omitempty"`    // Command
}

// Listener is one timeout: what happens once the user has been idle that
// long, and when they come back after it.
type Listener struct {
	Timeout   time.Duration `json:"timeout"`
	OnTimeout Action        `json:"onTimeout"`
	OnResume  Action        `json:"onResume"`
}

// Plan is what the settings arm: the dim, lock, screen-off and suspend
// steps whose timeout isn't 0, in timeout order (steps on the same
// timeout keep that order), then the user's own enabled listeners that
// run something.
func Plan(s Settings) []Listener {
	dimPercent := s.DimLevel
	if s.DimMode == "by" {
		dimPercent = s.DimBy
	}
	steps := []Listener{
		{Timeout: s.DimTimeout, OnTimeout: Action{Kind: Dim, Mode: s.DimMode, Percent: dimPercent}, OnResume: Action{Kind: Undim}},
		{Timeout: s.LockTimeout, OnTimeout: Action{Kind: Lock}},
		{Timeout: s.ScreenOffTimeout, OnTimeout: Action{Kind: ScreenOff}, OnResume: Action{Kind: ScreenOn}},
		{Timeout: s.SuspendTimeout, OnTimeout: Action{Kind: Suspend}},
	}
	steps = slices.DeleteFunc(steps, func(l Listener) bool { return l.Timeout <= 0 })
	slices.SortStableFunc(steps, func(a, b Listener) int { return int((a.Timeout - b.Timeout) / time.Millisecond) })
	for _, item := range s.Items {
		run := strings.TrimSpace(item.OnTimeout)
		if !item.Enabled || item.Timeout <= 0 || run == "" {
			continue
		}
		l := Listener{Timeout: item.Timeout, OnTimeout: Action{Kind: Command, Line: run}}
		if back := strings.TrimSpace(item.OnResume); back != "" {
			l.OnResume = Action{Kind: Command, Line: back}
		}
		steps = append(steps, l)
	}
	return steps
}
