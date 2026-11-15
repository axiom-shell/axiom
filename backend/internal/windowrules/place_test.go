package windowrules

import (
	"reflect"
	"testing"
)

func TestKeys(t *testing.T) {
	t.Parallel()
	all := WindowEffects{Float: true, Width: 1, Height: 2, Center: true, Workspace: "3", Follow: true, Special: Special{ID: "s"},
		Monitor: "DP-1", Fullscreen: true, Maximize: true, Pin: true, Opacity: 50, NoBlur: true, NoFocus: true, NoScreenShare: true, Tearing: true}
	want := []string{"monitor", "workspace", "follow", "special", "float", "size", "center", "fullscreen",
		"maximize", "pin", "opacity", "noBlur", "noFocus", "noScreenShare", "tearing"}
	if got := all.Keys(); !reflect.DeepEqual(got, want) {
		t.Errorf("all: %v", got)
	}
	if got := (WindowEffects{Follow: true}).Keys(); got != nil {
		t.Errorf("follow without a workspace: %v", got)
	}
	if got := (WindowEffects{Workspace: "3"}).Keys(); !reflect.DeepEqual(got, []string{"workspace"}) {
		t.Errorf("workspace only: %v", got)
	}
	if got := (WindowEffects{Width: 5}).Keys(); got != nil {
		t.Errorf("half a size: %v", got)
	}
}

// rm is a rule with a kind per index in kinds matching.
func rm(id string, w WindowEffects, kinds ...int) RuleMatch {
	return RuleMatch{Rule: Rule{ID: id, Window: w, Kinds: make([]Kind, 3)}, Kinds: kinds}
}

func TestPlanFor(t *testing.T) {
	t.Parallel()
	live := map[string]bool{"ruleLiveLook": true}
	// kind 0 is written, kind 1 live, kind 2 skipped
	row := func(id string, placed, dropped []string) Report {
		return Report{Rule: id, Placed: placed, Dropped: dropped, Live: []int{1}, Skipped: []int{2}}
	}
	fx := WindowEffects{Float: true, Width: 400, Height: 300, Center: true, Workspace: "3", Follow: true, Monitor: "DP-1",
		Fullscreen: true, Maximize: true, Pin: true, Opacity: 50, NoBlur: true, NoFocus: true, NoScreenShare: true, Tearing: true}
	full := Plan{Output: "DP-1", Workspace: "3", Follow: true, Float: true, Width: 400, Height: 300, Center: true, Fullscreen: true,
		Maximize: true, Pin: true, LookRules: []string{"a"}, Tearing: true}
	for name, tc := range map[string]struct {
		matches []RuleMatch
		reports map[string]Report
		support map[string]bool
		apply   bool
		want    Plan
	}{
		"live only: everything but noFocus": {
			matches: []RuleMatch{rm("a", fx, 1)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: live, want: full},
		"written match: nothing placed": {
			matches: []RuleMatch{rm("a", fx, 0)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: live},
		"written match: only placed": {
			matches: []RuleMatch{rm("a", fx, 0)}, reports: map[string]Report{"a": row("a", []string{"workspace"}, nil)}, support: live,
			want: Plan{Workspace: "3"}},
		"written and live kind: written wins": {
			matches: []RuleMatch{rm("a", fx, 0, 1)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: live},
		"skipped kind counts as not written": {
			matches: []RuleMatch{rm("a", fx, 2)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: live, want: full},
		"written match, apply: everything, no follow": {
			matches: []RuleMatch{rm("a", fx, 0)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: live, apply: true,
			want: func() Plan { p := full; p.Follow = false; return p }()},
		"dropped left out": {
			matches: []RuleMatch{rm("a", WindowEffects{Float: true, Pin: true, Opacity: 50}, 1)},
			reports: map[string]Report{"a": row("a", nil, []string{"pin", "opacity"})}, support: live, want: Plan{Float: true}},
		"no ruleLiveLook: no maximize, pin, look, tearing": {
			matches: []RuleMatch{rm("a", fx, 1)}, reports: map[string]Report{"a": row("a", nil, nil)}, support: nil,
			want: Plan{Output: "DP-1", Workspace: "3", Follow: true, Float: true, Width: 400, Height: 300, Center: true, Fullscreen: true}},
		"two rules: the higher one's size": {
			matches: []RuleMatch{rm("hi", WindowEffects{Float: true, Width: 1, Height: 2}, 1), rm("lo", WindowEffects{Float: true, Width: 3, Height: 4}, 1)},
			reports: map[string]Report{"hi": row("hi", nil, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Float: true, Width: 1, Height: 2}},
		"destination: the higher rule, with its own follow": {
			matches: []RuleMatch{rm("hi", WindowEffects{Special: Special{ID: "g"}}, 1), rm("lo", WindowEffects{Workspace: "2", Follow: true}, 1)},
			reports: map[string]Report{"hi": row("hi", nil, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Special: "g", Show: true}},
		"destination: a workspace over a lower special": {
			matches: []RuleMatch{rm("hi", WindowEffects{Workspace: "2", Follow: true}, 1), rm("lo", WindowEffects{Special: Special{ID: "g", Silent: true}}, 1)},
			reports: map[string]Report{"hi": row("hi", nil, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Workspace: "2", Follow: true}},
		"silent special isn't shown": {
			matches: []RuleMatch{rm("a", WindowEffects{Special: Special{ID: "g", Silent: true}}, 1)},
			reports: map[string]Report{"a": row("a", nil, nil)}, support: live, want: Plan{Special: "g"}},
		"look rules in priority order": {
			matches: []RuleMatch{rm("hi", WindowEffects{Opacity: 50}, 1), rm("none", WindowEffects{Float: true}, 1), rm("lo", WindowEffects{NoBlur: true}, 1)},
			reports: map[string]Report{"hi": row("hi", nil, nil), "none": row("none", nil, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Float: true, LookRules: []string{"hi", "lo"}}},
		"apply: a special isn't shown": {
			matches: []RuleMatch{rm("a", WindowEffects{Special: Special{ID: "g"}}, 1)},
			reports: map[string]Report{"a": row("a", nil, nil)}, support: live, apply: true, want: Plan{Special: "g"}},
		"no report row: nothing": {
			matches: []RuleMatch{rm("a", fx, 1)}, reports: map[string]Report{}, support: live},
		"niri-like row: workspace and follow placed": {
			matches: []RuleMatch{rm("a", fx, 0)}, reports: map[string]Report{"a": row("a", []string{"workspace", "follow"}, nil)}, support: live,
			want: Plan{Workspace: "3", Follow: true}},
		"written higher rule claims monitor, workspace and size from a lower live rule": {
			matches: []RuleMatch{rm("hi", WindowEffects{Workspace: "web", Monitor: "DP-2", Width: 1, Height: 2}, 0),
				rm("lo", WindowEffects{Workspace: "chat", Monitor: "DP-1", Width: 3, Height: 4, Float: true, Follow: true}, 1)},
			reports: map[string]Report{"hi": row("hi", nil, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Float: true}},
		"written higher rule: its placed workspace is the destination": {
			matches: []RuleMatch{rm("hi", WindowEffects{Workspace: "3"}, 0), rm("lo", WindowEffects{Workspace: "chat", Follow: true}, 1)},
			reports: map[string]Report{"hi": row("hi", []string{"workspace"}, nil), "lo": row("lo", nil, nil)}, support: live,
			want: Plan{Workspace: "3"}},
		"niri-like row: a named workspace's follow only": {
			matches: []RuleMatch{rm("a", fx, 0)}, reports: map[string]Report{"a": row("a", []string{"follow"}, nil)}, support: live,
			want: Plan{Follow: true}},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			if got := PlanFor(tc.matches, tc.reports, tc.support, tc.apply); !reflect.DeepEqual(got, tc.want) {
				t.Errorf("got  %+v\nwant %+v", got, tc.want)
			}
		})
	}
}

func TestBatches(t *testing.T) {
	t.Parallel()
	kinds := func(bs [][]Step) [][]StepKind {
		var out [][]StepKind
		for _, b := range bs {
			var ks []StepKind
			for _, s := range b {
				ks = append(ks, s.Kind)
			}
			out = append(out, ks)
		}
		return out
	}
	for name, tc := range map[string]struct {
		p          Plan
		fullscreen bool
		want       [][]StepKind
	}{
		"empty":          {Plan{}, false, nil},
		"workspace only": {Plan{Workspace: "3"}, false, [][]StepKind{{StepMove}}},
		"float size center workspace": {
			Plan{Workspace: "3", Float: true, Width: 4, Height: 5, Center: true}, false,
			[][]StepKind{{StepFloat}, {StepSize}, {StepCenter, StepMove}}},
		"float and workspace move together": {
			Plan{Workspace: "3", Float: true}, false, [][]StepKind{{StepMove, StepFloat}}},
		"last batch ends fullscreen, maximize, pin, focus": {
			Plan{Workspace: "3", Float: true, Width: 4, Height: 5, Center: true, Fullscreen: true, Maximize: true, Pin: true, Follow: true}, false,
			[][]StepKind{{StepFloat}, {StepSize}, {StepCenter, StepMove, StepFullscreen, StepMaximize, StepPin, StepFocus}}},
		"already fullscreen": {Plan{Fullscreen: true, Float: true}, true, [][]StepKind{{StepFloat}}},
		"fullscreen alone":   {Plan{Fullscreen: true}, false, [][]StepKind{{StepFullscreen}}},
		"output and look first": {
			Plan{Output: "DP-1", Workspace: "2", LookRules: []string{"a"}, Float: true}, false,
			[][]StepKind{{StepOutput, StepMove, StepFloat, StepLook}}},
		"tearing is a look":   {Plan{Tearing: true, LookRules: []string{"a"}}, false, [][]StepKind{{StepLook}}},
		"follow only":         {Plan{Follow: true}, false, [][]StepKind{{StepFocus}}},
		"centre without move": {Plan{Center: true}, false, [][]StepKind{{StepCenter}}},
	} {
		if got := kinds(tc.p.Batches(tc.fullscreen)); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: %v, want %v", name, got, tc.want)
		}
	}
	got := (Plan{Special: "g", Show: true, Width: 4, Height: 5}).Batches(false)
	if !reflect.DeepEqual(got[0][0], Step{Kind: StepMove, Special: "g", Show: true}) || got[1][0].Width != 4 {
		t.Errorf("step fields: %+v", got)
	}
}
