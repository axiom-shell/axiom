package procinfo

import (
	"bytes"
	"strings"
)

// Signal is one reason a window counts as a game; the inspector (PR 9)
// says which matched, in the shell's words.
type Signal string

const (
	SignalSteamApp  Signal = "steamApp" // its app id is steam_app_<N>
	SignalSteam     Signal = "steam"    // launched by Steam
	SignalProton    Signal = "proton"   // runs through Proton
	SignalLutris    Signal = "lutris"
	SignalHeroic    Signal = "heroic"
	SignalUmu       Signal = "umu"
	SignalGamescope Signal = "gamescope"
	SignalWine      Signal = "wine"
)

// The signal table. Steam counts only through `reaper SteamLaunch` or a
// game id, never a bare `steam` above the window (its own windows are not
// games); a launcher's own window is not a game either, so Lutris and Heroic
// count only through what runs the game (lutris-wrapper, legendary, gogdl,
// nile), not their UI process. Wine and gamescope count only together with
// a launcher signal: a bare `wine notepad` is not a game.
var (
	// signalOrder is the order signals come out in.
	signalOrder = []Signal{SignalSteam, SignalProton, SignalLutris, SignalHeroic, SignalUmu, SignalGamescope, SignalWine}

	// aboveNames: a process above the window named so gives the signal.
	aboveNames = map[string]Signal{
		"proton": SignalProton, "lutris-wrapper": SignalLutris,
		"legendary": SignalHeroic, "gogdl": SignalHeroic, "nile": SignalHeroic, "umu-run": SignalUmu,
		"gamescope": SignalGamescope, "gamescope-wl": SignalGamescope,
	}
	// ownNames: the window's own process named so gives the signal (also above).
	ownNames = map[string]Signal{"gamescope": SignalGamescope, "gamescope-wl": SignalGamescope}
	// exeNames: an exe basename of the window's process or one above it.
	exeNames = map[string]Signal{
		"wine": SignalWine, "wine64": SignalWine,
		"wine-preloader": SignalWine, "wine64-preloader": SignalWine,
	}
	// envNames: set, and neither empty nor 0, in the window's own environment.
	envNames = map[string]Signal{
		"SteamGameId": SignalSteam, "SteamAppId": SignalSteam,
		"STEAM_COMPAT_DATA_PATH": SignalProton, "LUTRIS_GAME_UUID": SignalLutris, "UMU_ID": SignalUmu,
		"HEROIC_APP_NAME": SignalHeroic,
	}
	// bridgeNames stand for many X11 windows at once.
	bridgeNames = map[string]bool{"xwayland-satellite": true, "Xwayland": true}
)

// signalsOf is the signals of a window's process tree, in table order:
// self, the nodes above it and its environment (NUL-separated, scanned and
// not kept).
func signalsOf(self node, above []node, environ []byte) []Signal {
	got := map[Signal]bool{}
	if s, ok := ownNames[self.name]; ok {
		got[s] = true
	}
	if s, ok := exeNames[self.exe]; ok {
		got[s] = true
	}
	for _, n := range above {
		if n.steamLaunch {
			got[SignalSteam] = true
		}
		if s, ok := aboveNames[n.name]; ok {
			got[s] = true
		}
		if s, ok := exeNames[n.exe]; ok {
			got[s] = true
		}
	}
	for _, e := range bytes.Split(environ, []byte{0}) {
		k, v, ok := strings.Cut(string(e), "=")
		if s, hit := envNames[k]; ok && hit && v != "" && v != "0" {
			got[s] = true
		}
	}
	if !got[SignalSteam] && !got[SignalProton] && !got[SignalLutris] && !got[SignalHeroic] && !got[SignalUmu] {
		return []Signal{} // wine and gamescope alone are not a game
	}
	out := []Signal{}
	for _, s := range signalOrder {
		if got[s] {
			out = append(out, s)
		}
	}
	return out
}

// Detect is why a window counts as a game: its app id's signal, then its
// process tree's (p nil: unknown process). Empty: not a game.
func Detect(appID string, p *Process) []Signal {
	var out []Signal
	if n, ok := strings.CutPrefix(appID, "steam_app_"); ok && n != "" && strings.Trim(n, "0123456789") == "" {
		out = append(out, SignalSteamApp)
	}
	if p != nil {
		out = append(out, p.Signals...)
	}
	return out
}
