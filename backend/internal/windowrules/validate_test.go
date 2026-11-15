package windowrules

import (
	"reflect"
	"testing"
)

func okRule(id string) Rule {
	return Rule{
		ID: id, Enabled: true,
		Kinds: []Kind{{Conditions: []Condition{{FieldAppID, OpIs, "x"}}}},
	}
}

func codes(issues []Issue) []string {
	out := []string{}
	for _, i := range issues {
		out = append(out, i.Code+"@"+i.Path)
	}
	return out
}

func TestValidate(t *testing.T) {
	t.Parallel()
	cond := func(f Field, op Op, v string) Rule {
		r := okRule("r")
		r.Kinds = []Kind{{Conditions: []Condition{{f, op, v}}}}
		return r
	}
	win := func(w WindowEffects) Rule { r := okRule("r"); r.Window = w; return r }
	shell := func(s ShellEffects) Rule { r := okRule("r"); r.Shell = s; return r }
	on := func(w When) Trigger { return Trigger{true, w} }
	for name, tc := range map[string]struct {
		rule Rule
		ctx  Context
		code string
		path string
		args []string
	}{
		"noKinds":      {Rule{ID: "r"}, Context{}, "noKinds", "windows", nil},
		"emptyKind":    {Rule{ID: "r", Kinds: []Kind{{}}}, Context{}, "emptyKind", "windows.0", nil},
		"opNotAllowed": {cond(FieldGame, OpMatches, ""), Context{}, "opNotAllowed", "windows.0.conditions.0.op", []string{"game"}},
		"emptyValue":   {cond(FieldTitle, OpIs, ""), Context{}, "emptyValue", "windows.0.conditions.0.value", nil},
		"patternInvalid": {cond(FieldTitle, OpMatches, "["), Context{}, "patternInvalid", "windows.0.conditions.0.value",
			[]string{"missing closing ]: `[`"}},
		"patternRefused": {cond(FieldTitle, OpMatches, `\bx`), Context{}, "patternRefused", "windows.0.conditions.0.value", []string{`\b`}},
		"steamGameId":    {cond(FieldSteamGame, OpIs, "x1"), Context{}, "steamGameId", "windows.0.conditions.0.value", nil},
		"twoTests": {Rule{ID: "r", Enabled: true, Kinds: []Kind{{Conditions: []Condition{
			{FieldAppID, OpIs, "a"}, {FieldSteamGame, OpIs, "1"}}}}}, Context{}, "twoTests", "windows.0.conditions.1", []string{"appId"}},
		"sizePair":             {win(WindowEffects{Width: 5}), Context{}, "sizePair", "window.size", nil},
		"workspaceAndSpecial":  {win(WindowEffects{Workspace: "2", Special: Special{ID: "s"}}), Context{}, "workspaceAndSpecial", "window.special.id", nil},
		"workspaceName0":       {win(WindowEffects{Workspace: "0"}), Context{}, "workspaceName", "window.workspace", nil},
		"workspaceOverflow":    {win(WindowEffects{Workspace: "99999999999999999999"}), Context{}, "workspaceName", "window.workspace", nil},
		"missingId":            {Rule{ID: "", Enabled: true, Kinds: okRule("").Kinds}, Context{}, "missingId", "id", nil},
		"emptyApp":             {cond(FieldApp, OpIs, ""), Context{}, "emptyValue", "windows.0.conditions.0.value", nil},
		"steamGameNot":         {cond(FieldSteamGame, OpIsNot, "x"), Context{}, "steamGameId", "windows.0.conditions.0.value", nil},
		"workspaceNameSpace":   {win(WindowEffects{Workspace: " a"}), Context{}, "workspaceName", "window.workspace", nil},
		"workspaceNameSpecial": {win(WindowEffects{Workspace: "special:x"}), Context{}, "workspaceName", "window.workspace", nil},
		"specialId":            {win(WindowEffects{Special: Special{ID: "a b"}}), Context{}, "specialId", "window.special.id", nil},
		"powerProfile":         {shell(ShellEffects{PowerProfile: PowerProfile{on(WhenOpen), "x"}}), Context{}, "powerProfile", "shell.powerProfile.profile", nil},
		"hideFromNothing":      {shell(ShellEffects{HideFrom: HideFrom{Trigger: on(WhenOpen)}}), Context{}, "hideFromNothing", "shell.hideFrom", nil},
		"pauseBindsNone":       {shell(ShellEffects{PauseBinds: PauseBinds{on(WhenFocused), "these", nil}}), Context{}, "pauseBindsNone", "shell.pauseBinds.binds", nil},
		"pauseBindsNoWayOut":   {shell(ShellEffects{PauseBinds: PauseBinds{on(WhenFocused), "allExcept", nil}}), Context{}, "pauseBindsNoWayOut", "shell.pauseBinds.binds", nil},
		"pauseBindsWhen":       {shell(ShellEffects{PauseBinds: PauseBinds{on(WhenOpen), "allExcept", []string{"a"}}}), Context{}, "pauseBindsWhen", "shell.pauseBinds.when", nil},
		"unknownBind":          {shell(ShellEffects{PauseBinds: PauseBinds{on(WhenFocused), "these", []string{"a", "z"}}}), Context{BindIDs: []string{"a"}}, "unknownBind", "shell.pauseBinds.binds.1", []string{"z"}},
		"unknownWhen":          {shell(ShellEffects{DND: Trigger{true, "never"}}), Context{}, "unknownWhen", "shell.dnd.when", nil},
	} {
		args := tc.args
		if args == nil {
			args = []string{}
		}
		got := Validate(Config{Rules: []Rule{tc.rule}}, tc.ctx)
		if len(got) != 1 || got[0].Code != tc.code || got[0].Path != tc.path || got[0].Rule != tc.rule.ID ||
			!reflect.DeepEqual(got[0].Args, args) || got[0].Message == "" {
			t.Errorf("%s: got %+v, want %s at %s args %v", name, got, tc.code, tc.path, args)
		}
	}
}

func TestValidateRest(t *testing.T) {
	t.Parallel()
	// A clean rule with every effect on.
	r := okRule("r")
	r.Window = WindowEffects{Float: true, Width: 1, Height: 1, Workspace: "2", Monitor: "gone", Opacity: 50}
	r.Shell = ShellEffects{
		DND: Trigger{true, WhenOpen}, KeepAwake: Trigger{true, WhenFocused},
		PowerProfile: PowerProfile{Trigger{true, WhenOpen}, "performance"},
		HideFrom:     HideFrom{Trigger: Trigger{true, WhenOpen}, Dock: true},
		PauseBinds:   PauseBinds{Trigger{true, WhenFocused}, "these", []string{"a"}},
		PauseOSD:     Trigger{true, WhenFocused}, HideBar: Trigger{true, WhenFullscreen},
	}
	if got := Validate(Config{Rules: []Rule{r}}, Context{BindIDs: []string{"a"}}); len(got) != 0 {
		t.Errorf("clean rule: %+v", got)
	}
	// Disabled effects aren't checked, an unknown bind list is skipped.
	d := okRule("d")
	d.Shell = ShellEffects{
		PowerProfile: PowerProfile{Profile: "x"}, HideFrom: HideFrom{}, DND: Trigger{When: "never"},
		PauseBinds: PauseBinds{Mode: "these"},
	}
	if got := Validate(Config{Rules: []Rule{d}}, Context{}); len(got) != 0 {
		t.Errorf("disabled effects: %+v", got)
	}
	u := okRule("u")
	u.Shell.PauseBinds = PauseBinds{Trigger{true, WhenFocused}, "these", []string{"zz"}}
	if got := Validate(Config{Rules: []Rule{u}}, Context{}); len(got) != 0 {
		t.Errorf("nil BindIDs: %+v", got)
	}
	// Issue order within a rule, then the switches.
	m := Rule{ID: "m", Enabled: true, Window: WindowEffects{Width: 1}}
	m.Shell.HideFrom = HideFrom{Trigger: Trigger{true, WhenOpen}}
	c := Config{Rules: []Rule{m}, Switches: Switches{GamesSpecial: GamesSpecial{Enabled: true}}}
	want := []string{"noKinds@windows", "sizePair@window.size", "hideFromNothing@shell.hideFrom", "specialMissing@switches.gamesSpecial.special.id"}
	if got := codes(Validate(c, Context{})); !reflect.DeepEqual(got, want) {
		t.Errorf("order: got %v, want %v", got, want)
	}
	c.Switches.GamesSpecial.Special.ID = "a b"
	if got := Validate(c, Context{}); got[len(got)-1].Code != "specialId" || got[len(got)-1].Rule != "" {
		t.Errorf("switch specialId: %+v", got)
	}
	// Negations, live kinds and an empty bind list.
	n := okRule("n")
	n.Kinds = []Kind{{Conditions: []Condition{{FieldAppID, OpIsNot, "a"}, {FieldAppID, OpIsNot, "b"}}}}
	l := okRule("l")
	l.Kinds = []Kind{{Conditions: []Condition{{FieldAppID, OpIs, "a"}, {FieldAppID, OpIs, "b"}, {FieldGame, OpIs, ""}}}}
	if got := Validate(Config{Rules: []Rule{n, l}}, Context{}); len(got) != 0 {
		t.Errorf("isNot twice / live kind: %+v", got)
	}
	ae := okRule("ae")
	ae.Shell.PauseBinds = PauseBinds{Trigger{true, WhenOpen}, "allExcept", nil}
	if got := codes(Validate(Config{Rules: []Rule{ae}}, Context{})); !reflect.DeepEqual(got,
		[]string{"pauseBindsNoWayOut@shell.pauseBinds.binds", "pauseBindsWhen@shell.pauseBinds.when"}) {
		t.Errorf("allExcept: %v", got)
	}
	ub := okRule("ub")
	ub.Shell.PauseBinds = PauseBinds{Trigger{true, WhenFocused}, "these", []string{"a", "b"}}
	if got := Validate(Config{Rules: []Rule{ub}}, Context{BindIDs: []string{}}); len(got) != 2 {
		t.Errorf("empty BindIDs: %+v", got)
	}
	// A way out that works: a kept bind that is paused or keyless is none.
	wo := okRule("wo")
	wo.Shell.PauseBinds = PauseBinds{Trigger{true, WhenFocused}, "allExcept", []string{"a", "b"}}
	for name, tc := range map[string]struct {
		ctx  Context
		want []string
	}{
		"all unbound":  {Context{BindIDs: []string{"a", "b"}, Unbound: []string{"a", "b"}}, []string{"pauseBindsWayOutOff@shell.pauseBinds.binds"}},
		"one works":    {Context{BindIDs: []string{"a", "b"}, Unbound: []string{"a"}}, []string{}},
		"unknown kept": {Context{BindIDs: []string{"a"}, Unbound: []string{"a"}}, []string{"unknownBind@shell.pauseBinds.binds.1"}},
		"unknown ids":  {Context{}, []string{}},
	} {
		if got := codes(Validate(Config{Rules: []Rule{wo}}, tc.ctx)); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("way out %s: got %v, want %v", name, got, tc.want)
		}
	}
	// Duplicate ids.
	dup := Validate(Config{Rules: []Rule{okRule("x"), okRule("x")}}, Context{})
	if got := codes(dup); !reflect.DeepEqual(got, []string{"duplicateId@id"}) {
		t.Errorf("duplicate: %v", got)
	}
	// A built-in rule's id is taken
	if got := codes(Validate(Config{Rules: []Rule{okRule("_steamFloat")}}, Context{})); !reflect.DeepEqual(got, []string{"duplicateId@id"}) {
		t.Errorf("built-in id: %v", got)
	}
}

func TestUsable(t *testing.T) {
	t.Parallel()
	off := okRule("off")
	off.Enabled = false
	bad := okRule("bad")
	bad.Kinds = nil
	noID := okRule("")
	c := Config{
		Rules:    []Rule{okRule("a"), off, bad, noID, okRule("d"), okRule("d"), okRule("b")},
		Switches: Switches{GamesSpecial: GamesSpecial{Enabled: true}},
	}
	var ids []string
	for _, r := range Usable(c, Validate(c, Context{})) {
		ids = append(ids, r.ID)
	}
	if !reflect.DeepEqual(ids, []string{"a", "b"}) {
		t.Errorf("got %v", ids)
	}
	only := Config{Rules: []Rule{okRule("a")}, Switches: c.Switches}
	if got := Usable(only, Validate(only, Context{})); len(got) != 1 {
		t.Errorf("switch issues dropped a rule: %v", got)
	}
}
