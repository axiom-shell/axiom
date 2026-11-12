package manager

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/compositor/takeover"
	"github.com/axiom-shell/axiom/backend/internal/compositor/userconf"
	"github.com/axiom-shell/axiom/backend/internal/hookup"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// StartPattern is the regexp finding a line that starts axiom
// (Paths.startPattern): `axiom run`, however the binary is spelled.
const StartPattern = `(^|[\s'"/])axiom['"]? +run\b`

// Offline is one compositor's writer without the compositor: what its
// files and the lines axiom adds to the user's config are, read from the
// files only (the uninstall's, which runs with no compositor to ask). It
// has no tables or schema, so only what the paths and lines need.
type Offline struct {
	kind   string
	w      writer
	in     Inputs
	getenv func(string) string
}

// NewOffline is the writer of kind ("hyprland", "sway" or "niri"), with bin
// the binary a line starting axiom would name (quoted by the writer as the
// shell quotes it).
func NewOffline(getenv func(string) string, kind, bin string) (*Offline, bool) {
	e := env{getenv: getenv, stateDir: xdg.Resolve(getenv).State, schema: func() any { return nil },
		logf: func(string, ...any) {}, state: &runtimeState{}, carried: true}
	o := &Offline{kind: kind, getenv: getenv,
		in: Inputs{jsonx.Obj("ctx", jsonx.Obj("shellCommand", "'"+bin+"'"), "startPattern", StartPattern)}}
	switch kind {
	case "hyprland":
		o.w = newHypr(e, nil)
	case "sway":
		o.w = newSway(e, nil)
	case "niri":
		o.w = newNiri(e, nil)
	default:
		return nil, false
	}
	return o, true
}

// Kind is the compositor's name.
func (o *Offline) Kind() string { return o.kind }

// ConfigDir is the compositor's config folder (~/.config/hypr).
func (o *Offline) ConfigDir() string { return o.w.files(o.in).ConfigDir }

// ManagedPath is the config a takeover makes axiom's.
func (o *Offline) ManagedPath() string { return o.w.files(o.in).ManagedPath }

// Main is the user's config the include and autostart lines go in.
func (o *Offline) Main() string {
	f := o.w.files(o.in)
	if file, _ := f.AutostartTarget.Value("file").(string); file != "" {
		return file
	}
	return f.ManagedPath
}

// Takeover is what releasing the managed config takes: the fallback is the
// released text without a line starting axiom (nothing is left to start it
// or load its module).
func (o *Offline) Takeover() takeover.Options {
	kind, _ := takeover.KindNamed(o.w.takeoverKind())
	f := o.w.files(o.in)
	var fallback string
	switch w := o.w.(type) {
	case *hyprWriter:
		fallback = render.ReleasedLua(w.dir()+"user", "")
	case *swayWriter:
		fallback = render.SwayReleasedText(w.dir()+"user", "")
	case *niriWriter:
		fallback = render.NiriReleasedText(w.userDir(), strs(userconf.NiriUserFiles(w.userDir())), jsonx.Arr(), jsonx.Arr())
	}
	// Nothing starts axiom in it any more: its header doesn't say it does
	fallback = strings.NewReplacer("It starts axiom and loads", "It loads", "It starts axiom and includes", "It includes").Replace(fallback)
	return takeover.Options{Kind: kind, Dir: f.ConfigDir, Header: o.w.header(), Fallback: fallback,
		Getenv: o.getenv, Elsewhere: f.RunsElsewhere}
}

// Targets are the hookup targets of the lines that load axiom's module and
// start it, as the compositor card applies them.
func (o *Offline) Targets() []hookup.Target {
	f := o.w.files(o.in)
	var out []hookup.Target
	for _, t := range []*jsonx.Object{f.IncludeTarget, f.AutostartTarget} {
		if t == nil {
			continue
		}
		var target hookup.Target
		if err := json.Unmarshal(jsonx.MarshalCompact(t), &target); err == nil {
			out = append(out, target)
		}
	}
	return out
}

// Exists says whether the compositor's config dir is there at all.
func (o *Offline) Exists() bool {
	_, err := os.Stat(filepath.Clean(o.ConfigDir()))
	return err == nil
}
