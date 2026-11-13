// Package windowrules is the model of the user's window rules (config.json's WindowRules): the section parsed into rules, their validation into issues the editor shows, the patterns their conditions become, and which kinds of window a compositor's config can match and which only the daemon can. Pure: no I/O.
package windowrules

import "github.com/axiom-shell/axiom/backend/internal/jsonx"

// Field is what a condition tests of a window.
type Field string

// The fields a condition can test.
const (
	FieldAppID       Field = "appId"
	FieldTitle       Field = "title"
	FieldProcess     Field = "process"
	FieldStartedFrom Field = "startedFrom"
	FieldXwayland    Field = "xwayland"
	FieldGame        Field = "game"
	FieldSteamGame   Field = "steamGame"
	FieldApp         Field = "app"
)

// Op is how a condition tests its field.
type Op string

// The ways to test a field.
const (
	OpIs       Op = "is"
	OpContains Op = "contains"
	OpMatches  Op = "matches"
	OpIsNot    Op = "isNot"
)

// When is while what a shell effect is on.
type When string

// The moments a shell effect can be on for.
const (
	WhenOpen       When = "open"
	WhenFocused    When = "focused"
	WhenFullscreen When = "fullscreen"
)

// Config is the WindowRules section.
type Config struct {
	Rules    []Rule
	Switches Switches
}

// Rule is one window rule; its place in Config.Rules is its priority.
type Rule struct {
	ID, Name, Icon string
	Enabled        bool
	Kinds          []Kind        // config key "windows"
	Window         WindowEffects // config key "window"
	Shell          ShellEffects  // config key "shell"
}

// Kind is one kind of window: every condition must hold.
type Kind struct{ Conditions []Condition }

// Condition is one test of a window.
type Condition struct {
	Field Field
	Op    Op
	Value string
}

// WindowEffects are what the compositor's config does when a window opens;
// the zero value of each is "unset".
type WindowEffects struct {
	Float                     bool
	Width, Height             int
	Center                    bool
	Workspace                 string
	Follow                    bool // go to the workspace too
	Special                   Special
	Monitor                   string
	Fullscreen, Maximize, Pin bool
	Opacity                   int
	NoBlur, NoFocus           bool
	NoScreenShare, Tearing    bool
}

// Special is a special workspace to send a window to.
type Special struct {
	ID     string
	Silent bool
}

// Trigger is a shell effect's switch and the moment it's on for.
type Trigger struct {
	Enabled bool
	When    When
}

// ShellEffects are axiom's own effects while a window is open, focused or
// fullscreen.
type ShellEffects struct {
	DND, KeepAwake Trigger
	PowerProfile   PowerProfile
	HideFrom       HideFrom
	PauseBinds     PauseBinds
	PauseOSD       Trigger // config key "pauseOsd"
	HideBar        Trigger
}

// PowerProfile is the profile to hold: "performance" or "powerSaver".
type PowerProfile struct {
	Trigger
	Profile string
}

// HideFrom lists the places to hide the window from.
type HideFrom struct {
	Trigger
	Dock, Switcher, Workspaces, Launcher bool
}

// PauseBinds pauses keybinds by id; Mode is "these" or "allExcept".
type PauseBinds struct {
	Trigger
	Mode  string
	Binds []string
}

// Switches are the built-in rules, ranked below the user's own.
type Switches struct {
	SteamFloat   bool
	GamesSpecial GamesSpecial
}

// GamesSpecial sends games to a special workspace.
type GamesSpecial struct {
	Enabled bool
	Special Special
}

// Parse reads the WindowRules section (its jsonx tree, defaults filled). A
// missing or mistyped key reads as its zero value: no default is restated in Go.
func Parse(section any) Config {
	root := obj(section)
	var c Config
	for _, r := range list(root, "rules") {
		c.Rules = append(c.Rules, parseRule(obj(r)))
	}
	sw := obj(root.Value("switches"))
	gs := obj(sw.Value("gamesSpecial"))
	c.Switches = Switches{
		SteamFloat: flag(sw, "steamFloat"),
		GamesSpecial: GamesSpecial{
			Enabled: flag(gs, "enabled"),
			Special: parseSpecial(obj(gs.Value("special"))),
		},
	}
	return c
}

func parseRule(o *jsonx.Object) Rule {
	r := Rule{
		ID:      str(o, "id"),
		Name:    str(o, "name"),
		Icon:    str(o, "icon"),
		Enabled: flag(o, "enabled"),
	}
	for _, k := range list(o, "windows") {
		var kind Kind
		for _, c := range list(obj(k), "conditions") {
			co := obj(c)
			kind.Conditions = append(kind.Conditions, Condition{
				Field: Field(str(co, "field")), Op: Op(str(co, "op")), Value: str(co, "value"),
			})
		}
		r.Kinds = append(r.Kinds, kind)
	}
	w := obj(o.Value("window"))
	size := obj(w.Value("size"))
	r.Window = WindowEffects{
		Float: flag(w, "float"), Width: num(size, "width"), Height: num(size, "height"),
		Center: flag(w, "center"), Workspace: str(w, "workspace"), Follow: flag(w, "follow"),
		Special: parseSpecial(obj(w.Value("special"))), Monitor: str(w, "monitor"),
		Fullscreen: flag(w, "fullscreen"), Maximize: flag(w, "maximize"), Pin: flag(w, "pin"),
		Opacity: num(w, "opacity"), NoBlur: flag(w, "noBlur"), NoFocus: flag(w, "noFocus"),
		NoScreenShare: flag(w, "noScreenShare"), Tearing: flag(w, "tearing"),
	}
	s := obj(o.Value("shell"))
	pb := obj(s.Value("pauseBinds"))
	pp := obj(s.Value("powerProfile"))
	hf := obj(s.Value("hideFrom"))
	r.Shell = ShellEffects{
		DND:          trigger(obj(s.Value("dnd"))),
		KeepAwake:    trigger(obj(s.Value("keepAwake"))),
		PowerProfile: PowerProfile{Trigger: trigger(pp), Profile: str(pp, "profile")},
		HideFrom: HideFrom{
			Trigger: trigger(hf), Dock: flag(hf, "dock"), Switcher: flag(hf, "switcher"),
			Workspaces: flag(hf, "workspaces"), Launcher: flag(hf, "launcher"),
		},
		PauseBinds: PauseBinds{Trigger: trigger(pb), Mode: str(pb, "mode")},
		PauseOSD:   trigger(obj(s.Value("pauseOsd"))),
		HideBar:    trigger(obj(s.Value("hideBar"))),
	}
	for _, b := range list(pb, "binds") {
		if id, ok := b.(string); ok {
			r.Shell.PauseBinds.Binds = append(r.Shell.PauseBinds.Binds, id)
		}
	}
	return r
}

func parseSpecial(o *jsonx.Object) Special {
	return Special{ID: str(o, "id"), Silent: flag(o, "silent")}
}

func trigger(o *jsonx.Object) Trigger {
	return Trigger{Enabled: flag(o, "enabled"), When: When(str(o, "when"))}
}

// BindIDs are the ids of the Keybinds section's binds, for Context.
func BindIDs(keybinds any) []string {
	var ids []string
	for _, b := range list(obj(keybinds), "binds") {
		if id := str(obj(b), "id"); id != "" {
			ids = append(ids, id)
		}
	}
	return ids
}

// obj is v as an object, or an empty one (every read of it is then zero).
func obj(v any) *jsonx.Object {
	if o, ok := jsonx.AsObject(v); ok {
		return o
	}
	return jsonx.NewObject()
}

func str(o *jsonx.Object, key string) string {
	s, _ := o.Value(key).(string)
	return s
}

func flag(o *jsonx.Object, key string) bool {
	b, _ := o.Value(key).(bool)
	return b
}

func num(o *jsonx.Object, key string) int {
	v := o.Value(key)
	if f, ok := v.(float64); ok && jsonx.IsInteger(v) {
		return int(f)
	}
	return 0
}

func list(o *jsonx.Object, key string) []any {
	if a, ok := jsonx.AsArray(o.Value(key)); ok {
		return a.Items
	}
	return nil
}

// effectKeys are the effect keys (schema keys) in the order a compositor's
// config writes them; follow comes with workspace (Keys).
var effectKeys = []string{"monitor", "workspace", "follow", "special", "float", "size", "center", "fullscreen",
	"maximize", "pin", "opacity", "noBlur", "noFocus", "noScreenShare", "tearing"}

// Keys are the effects (schema keys) a rule sets, in the order they're
// written; follow is listed only with a workspace.
func (w WindowEffects) Keys() []string {
	var keys []string
	for _, key := range effectKeys {
		if w.has(key) {
			keys = append(keys, key)
		}
	}
	return keys
}

// has is whether the rule sets the effect (its value isn't "unset").
func (w WindowEffects) has(key string) bool {
	switch key {
	case "monitor":
		return w.Monitor != ""
	case "workspace":
		return w.Workspace != ""
	case "follow":
		return w.Follow && w.Workspace != ""
	case "special":
		return w.Special.ID != ""
	case "float":
		return w.Float
	case "size":
		return w.Width != 0 && w.Height != 0
	case "center":
		return w.Center
	case "fullscreen":
		return w.Fullscreen
	case "maximize":
		return w.Maximize
	case "pin":
		return w.Pin
	case "opacity":
		return w.Opacity != 0
	case "noBlur":
		return w.NoBlur
	case "noFocus":
		return w.NoFocus
	case "noScreenShare":
		return w.NoScreenShare
	case "tearing":
		return w.Tearing
	}
	return false
}

// LookKey is whether the effect is a rule's look, which the daemon can give
// an open window by its own commands or a tag (opacity, noBlur,
// noScreenShare, tearing).
func LookKey(key string) bool {
	return key == "opacity" || key == "noBlur" || key == "noScreenShare" || key == "tearing"
}
