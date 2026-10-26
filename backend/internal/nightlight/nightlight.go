// Package nightlight warms the screens' colors for the night light (the
// NightLight section), in place of hyprsunset and wlsunset: a color
// transform where the compositor has one (Hyprland's CTM, wayland/ctm),
// else gamma ramps (wayland/gamma), whichever its globals offer. The
// shell keeps the schedule and says what to show (nightlight.set); the
// daemon keeps it applied through hotplug until told otherwise.
package nightlight

import (
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/wayland/ctm"
	"github.com/axiom-shell/axiom/backend/internal/wayland/gamma"
)

// Modes: how the screens are warmed
const (
	ModeCTM   = "ctm"
	ModeGamma = "gamma"
)

// Settings are what the shell asks for.
type Settings struct {
	On          bool `json:"on"`
	Temperature int  `json:"temperature"` // kelvin
	Gamma       int  `json:"gamma"`       // percent of full brightness
}

// State is what the shell is told (nightlight.state).
type State struct {
	Settings
	// Mode is "ctm", "gamma" or "" (neither offered)
	Mode string `json:"mode"`
	// Blocked: another program holds the screens' colors
	Blocked bool `json:"blocked"`
}

// Options configure the service.
type Options struct {
	CTM   *ctm.Control
	Gamma *gamma.Control
	// OnState is told every new state
	OnState func(State)
}

// Service applies the night light.
type Service struct {
	o Options

	mu   sync.Mutex
	want Settings
	last *State
}

// New returns a service with the night light off.
func New(o Options) *Service { return &Service{o: o} }

// Mode is how the screens can be warmed here, "" when they can't.
func (s *Service) Mode() string {
	switch {
	case s.o.CTM.Available():
		return ModeCTM
	case s.o.Gamma.Available():
		return ModeGamma
	}
	return ""
}

// Set applies settings.
func (s *Service) Set(st Settings) {
	s.mu.Lock()
	s.want = st
	s.mu.Unlock()
	s.Changed()
}

// State is the state now.
func (s *Service) State() State {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.stateLocked()
}

func (s *Service) stateLocked() State {
	mode := s.Mode()
	blocked := mode == ModeCTM && s.o.CTM.Blocked() || mode == ModeGamma && s.o.Gamma.Blocked()
	return State{Settings: s.want, Mode: mode, Blocked: blocked}
}

// Changed applies the settings again: a protocol came or went, or
// another client took the colors. Its clients call it.
func (s *Service) Changed() {
	s.mu.Lock()
	st := s.want
	mode := s.Mode()
	r, g, b := Whitepoint(st.Temperature, float64(st.Gamma)/100)
	on := st.On && st.Temperature > 0
	// The one not in use gives its outputs back
	s.o.CTM.Set(on && mode == ModeCTM, Matrix(r, g, b))
	if on && mode == ModeGamma {
		s.o.Gamma.Set(func(size int) []uint16 { return Ramps(size, r, g, b) })
	} else {
		s.o.Gamma.Set(nil)
	}
	state := s.stateLocked()
	changed := s.last == nil || *s.last != state
	s.last = &state
	s.mu.Unlock()
	if changed && s.o.OnState != nil {
		s.o.OnState(state)
	}
}
