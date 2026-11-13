package windowrules

import (
	"slices"
	"sort"
)

// Moment is a window now, for the triggers; Focused includes the 500 ms
// after it lost focus (the engine's grace).
type Moment struct{ Focused, Fullscreen bool }

// On: the effect is switched on and its trigger holds for a window at m.
func (t Trigger) On(m Moment) bool {
	if !t.Enabled {
		return false
	}
	switch t.When {
	case WhenOpen:
		return true
	case WhenFocused:
		return m.Focused
	case WhenFullscreen:
		return m.Fullscreen
	}
	return false
}

// Active is one usable rule matching one open window.
type Active struct {
	Rule     Rule
	Priority int    // its place in the usable rules, 0 highest
	Window   string // the window's id
	Output   string
	Moment   Moment
}

// Holds are the while-effects in force, merged across rules.
type Holds struct {
	DND          []string     `json:"dnd"`       // the rules holding it, priority order
	KeepAwake    []string     `json:"keepAwake"` // the rules holding it, priority order
	PowerProfile ProfileHold  `json:"powerProfile"`
	HideFrom     HideFromHold `json:"hideFrom"`
	PauseBinds   BindsHold    `json:"pauseBinds"`
	PauseOSD     []string     `json:"pauseOsd"` // outputs, sorted
	HideBar      []string     `json:"hideBar"`  // outputs, sorted
}

// ProfileHold is the highest-priority rule's profile; both "" when none.
type ProfileHold struct {
	Profile string `json:"profile"`
	Rule    string `json:"rule"`
}

// HideFromHold is, per place, the ids of the windows to hide from it, sorted.
type HideFromHold struct {
	Dock       []string `json:"dock"`
	Switcher   []string `json:"switcher"`
	Workspaces []string `json:"workspaces"`
	Launcher   []string `json:"launcher"`
}

// BindsHold is the binds to pause: every bind but Keep when AllExcept, else
// These. A kept bind is never in These, so each all-except rule's way out
// stays usable.
type BindsHold struct {
	Rules     []string `json:"rules"`
	AllExcept bool     `json:"allExcept"`
	Keep      []string `json:"keep"`
	These     []string `json:"these"`
}

// Hold merges the active rules' effects: dnd, keepAwake and pauseBinds are
// held by every rule that holds them, hideFrom, pauseOsd and hideBar are the
// union over the windows held, and the power profile is the
// highest-priority rule's. No list is nil, so equal holds marshal equal.
func Hold(active []Active) Holds {
	active = slices.Clone(active)
	sort.SliceStable(active, func(i, j int) bool { return active[i].Priority < active[j].Priority })
	h := Holds{
		DND: []string{}, KeepAwake: []string{}, PauseOSD: []string{}, HideBar: []string{},
		HideFrom:   HideFromHold{Dock: []string{}, Switcher: []string{}, Workspaces: []string{}, Launcher: []string{}},
		PauseBinds: BindsHold{Rules: []string{}, Keep: []string{}, These: []string{}},
	}
	var these []string
	for _, a := range active {
		s, m := a.Rule.Shell, a.Moment
		if s.DND.On(m) {
			h.DND = addOnce(h.DND, a.Rule.ID)
		}
		if s.KeepAwake.On(m) {
			h.KeepAwake = addOnce(h.KeepAwake, a.Rule.ID)
		}
		if s.PowerProfile.On(m) && h.PowerProfile.Rule == "" {
			h.PowerProfile = ProfileHold{Profile: s.PowerProfile.Profile, Rule: a.Rule.ID}
		}
		if s.HideFrom.On(m) {
			for _, p := range []struct {
				on  bool
				ids *[]string
			}{
				{s.HideFrom.Dock, &h.HideFrom.Dock}, {s.HideFrom.Switcher, &h.HideFrom.Switcher},
				{s.HideFrom.Workspaces, &h.HideFrom.Workspaces}, {s.HideFrom.Launcher, &h.HideFrom.Launcher},
			} {
				if p.on {
					*p.ids = addOnce(*p.ids, a.Window)
				}
			}
		}
		if s.PauseBinds.On(m) {
			h.PauseBinds.Rules = addOnce(h.PauseBinds.Rules, a.Rule.ID)
			if s.PauseBinds.Mode == "allExcept" {
				h.PauseBinds.AllExcept = true
				for _, b := range s.PauseBinds.Binds {
					h.PauseBinds.Keep = addOnce(h.PauseBinds.Keep, b)
				}
			} else {
				for _, b := range s.PauseBinds.Binds {
					these = addOnce(these, b)
				}
			}
		}
		if a.Output != "" {
			if s.PauseOSD.On(m) {
				h.PauseOSD = addOnce(h.PauseOSD, a.Output)
			}
			if s.HideBar.On(m) {
				h.HideBar = addOnce(h.HideBar, a.Output)
			}
		}
	}
	for _, b := range these {
		if !slices.Contains(h.PauseBinds.Keep, b) {
			h.PauseBinds.These = append(h.PauseBinds.These, b)
		}
	}
	for _, l := range []*[]string{&h.PauseOSD, &h.HideBar, &h.HideFrom.Dock, &h.HideFrom.Switcher, &h.HideFrom.Workspaces, &h.HideFrom.Launcher} {
		sort.Strings(*l)
	}
	return h
}

func addOnce(list []string, s string) []string {
	if slices.Contains(list, s) {
		return list
	}
	return append(list, s)
}

// Look is what the sway look must leave to the rules: a window a rule sets
// the opacity of or turns the blur off for keeps those.
type Look struct {
	Opacity map[string]int `json:"opacity"` // window id → the highest-priority matching rule's opacity, in percent
	NoBlur  []string       `json:"noBlur"`  // window ids, sorted
}

// LookOf is Look from every usable rule matching each window (not the triggers).
func LookOf(matches []Active) Look {
	l := Look{Opacity: map[string]int{}, NoBlur: []string{}}
	best := map[string]int{}
	for _, a := range matches {
		if o := a.Rule.Window.Opacity; o > 0 {
			if p, ok := best[a.Window]; !ok || a.Priority < p {
				best[a.Window] = a.Priority
				l.Opacity[a.Window] = o
			}
		}
		if a.Rule.Window.NoBlur {
			l.NoBlur = addOnce(l.NoBlur, a.Window)
		}
	}
	sort.Strings(l.NoBlur)
	return l
}
