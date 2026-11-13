package windowrules

import "slices"

// Report is what the compositor's config does with a usable rule
// (compositor.state's windowRules.rules row).
type Report struct {
	Rule    string   `json:"rule"`
	Placed  []string `json:"placed"`
	Dropped []string `json:"dropped"`
	Live    []int    `json:"live"`
	Skipped []int    `json:"skipped"`
}

// RuleMatch is a usable rule matching a window, with the kinds that matched
// (indices into Rule.Kinds).
type RuleMatch struct {
	Rule  Rule
	Kinds []int
}

// Plan is what one window is given (PlanFor); zero values: nothing.
type Plan struct {
	Output             string
	Workspace, Special string // at most one set
	Show               bool   // a special: shown, not silent
	Follow             bool
	Float              bool
	Width, Height      int
	Center, Fullscreen bool
	Maximize, Pin      bool
	LookRules          []string // rule ids giving a look effect, priority order
	Tearing            bool
}

// liveLook is the capability a compositor needs for a window to be given a
// rule's look after it opened.
const liveLook = "ruleLiveLook"

// effectsOf is what rule m gives its window: only what the config leaves to
// the daemon (the report's placed) when a kind the config writes matched; else
// all the rule sets, less what the compositor can't do. "Don't focus when it
// opens" means nothing after open, and the look needs the capability.
func effectsOf(m RuleMatch, rep Report, supports map[string]bool, apply bool) []string {
	written := !apply && slices.ContainsFunc(m.Kinds, func(k int) bool {
		return !slices.Contains(rep.Live, k) && !slices.Contains(rep.Skipped, k)
	})
	if written {
		return rep.Placed
	}
	var keys []string
	for _, key := range m.Rule.Window.Keys() {
		switch {
		case key == "noFocus", slices.Contains(rep.Dropped, key):
		case (LookKey(key) || key == "maximize" || key == "pin") && !supports[liveLook]:
		default:
			keys = append(keys, key)
		}
	}
	return keys
}

// PlanFor merges the matching rules' effects for one window; matches are
// highest priority first, reports by rule id, apply: Apply to open windows
// (every matching rule, written or not; never follows, a special is moved
// silently). Per effect the highest rule giving it wins; the destination is
// the highest rule giving a workspace or a special, with its own follow and
// shown/silent; the look is every rule giving any of it.
func PlanFor(matches []RuleMatch, reports map[string]Report, supports map[string]bool, apply bool) Plan {
	var p Plan
	var dest, follow, size, output bool
	for _, m := range matches {
		rep, ok := reports[m.Rule.ID]
		if !ok {
			continue
		}
		w := m.Rule.Window
		look := false
		keys := effectsOf(m, rep, supports, apply)
		for _, key := range keys {
			switch key {
			case "monitor":
				if !output {
					p.Output, output = w.Monitor, true
				}
			case "workspace":
				if !dest {
					p.Workspace, dest = w.Workspace, true
					follow = slices.Contains(keys, "follow")
				}
			case "special":
				if !dest {
					p.Special, p.Show, dest = w.Special.ID, !w.Special.Silent, true
				}
			case "follow":
				// niri's config writes the workspace but not the follow
				if !dest {
					follow = true
				}
			case "float":
				p.Float = true
			case "size":
				if !size {
					p.Width, p.Height, size = w.Width, w.Height, true
				}
			case "center":
				p.Center = true
			case "fullscreen":
				p.Fullscreen = true
			case "maximize":
				p.Maximize = true
			case "pin":
				p.Pin = true
			case "tearing":
				p.Tearing, look = true, true
			default: // opacity, noBlur, noScreenShare
				look = true
			}
		}
		if look {
			p.LookRules = append(p.LookRules, m.Rule.ID)
		}
	}
	p.Follow = follow && !apply
	if apply {
		p.Show = false
	}
	return p
}

// StepKind is one placement step; it marshals as its name.
type StepKind string

// The placement steps.
const (
	StepOutput     StepKind = "output"
	StepMove       StepKind = "move"
	StepFloat      StepKind = "float"
	StepSize       StepKind = "size"
	StepCenter     StepKind = "center"
	StepFullscreen StepKind = "fullscreen"
	StepMaximize   StepKind = "maximize"
	StepPin        StepKind = "pin"
	StepLook       StepKind = "look"
	StepFocus      StepKind = "focus"
)

// Step is one thing done to a window; only the fields of its kind are set.
type Step struct {
	Kind               StepKind
	Output             string   // output
	Workspace, Special string   // move
	Show               bool     // move: show the special
	Width, Height      int      // size
	Rules              []string // look: the rules whose look it takes
	Tearing            bool     // look
}

// Batches are the plan's steps in order, each batch sent Settle after the one
// before. Batch 1 holds output, the move (unless centring), float and look;
// then size alone, since sway loses a size sent at open and niri centres by
// the old size until the new one is set; then center followed by the move,
// since sway's center pulls a floating window onto the shown workspace; the
// last ends with fullscreen (left out when fullscreen: the window is already),
// maximize, pin (needs a floating window on Hyprland), focus (follow).
// Empty: nothing to do.
func (p Plan) Batches(fullscreen bool) [][]Step {
	move := Step{Kind: StepMove, Workspace: p.Workspace, Special: p.Special, Show: p.Show}
	hasMove := p.Workspace != "" || p.Special != ""
	var first []Step
	if p.Output != "" {
		first = append(first, Step{Kind: StepOutput, Output: p.Output})
	}
	if hasMove && !p.Center {
		first = append(first, move)
	}
	if p.Float {
		first = append(first, Step{Kind: StepFloat})
	}
	if len(p.LookRules) > 0 || p.Tearing {
		first = append(first, Step{Kind: StepLook, Rules: p.LookRules, Tearing: p.Tearing})
	}
	var out [][]Step
	if len(first) > 0 {
		out = append(out, first)
	}
	if p.Width != 0 && p.Height != 0 {
		out = append(out, []Step{{Kind: StepSize, Width: p.Width, Height: p.Height}})
	}
	if p.Center {
		batch := []Step{{Kind: StepCenter}}
		if hasMove {
			batch = append(batch, move)
		}
		out = append(out, batch)
	}
	var last []Step
	if p.Fullscreen && !fullscreen {
		last = append(last, Step{Kind: StepFullscreen})
	}
	if p.Maximize {
		last = append(last, Step{Kind: StepMaximize})
	}
	if p.Pin {
		last = append(last, Step{Kind: StepPin})
	}
	if p.Follow {
		last = append(last, Step{Kind: StepFocus})
	}
	switch {
	case len(last) == 0:
	case len(out) == 0:
		out = append(out, last)
	default:
		out[len(out)-1] = append(out[len(out)-1], last...)
	}
	return out
}
