package manager

import (
	"sync/atomic"

	"github.com/axiom-shell/axiom/backend/internal/compositor/render"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// runtimeLayer is what every compositor's runtime layer shares (detached,
// and the fallback of the file modes while their file isn't loaded): the
// compositor's binds are read first, so a bind on a key the user's config
// already takes is skipped (skippedKeys).
type runtimeLayer struct {
	logf       func(format string, args ...any)
	configName string // "Hyprland", "sway"
	// reloads: config reloads seen (the event stream counts them); one
	// while the binds were read makes what was read stale
	reloads  atomic.Int64
	skipped  []string
	applied  []any
	reported map[string]bool
}

// read reads the binds in effect, again when the compositor reloaded
// meanwhile (another config's keys, or none while its file was replaced)
func (r *runtimeLayer) read(read func() (any, any, bool)) (entries, context any, ok bool) {
	for range 3 {
		start := r.reloads.Load()
		entries, context, ok = read()
		if r.reloads.Load() == start {
			return entries, context, ok
		}
	}
	return entries, context, ok
}

// plan is axiom's binds the compositor can bind that are free, logging
// each key taken once
func (r *runtimeLayer) plan(in Inputs, canBind func(any) bool, entries any) []any {
	var bindable []any
	for _, b := range itemsOf(activeBinds(in)) {
		if canBind(b) {
			bindable = append(bindable, b)
		}
	}
	plan := render.RuntimeBinds(jsonx.Arr(bindable...), orNil(entries, jsonx.Arr()))
	for _, key := range strList(plan.Value("unreadable")) {
		r.logf("Can't read the key %q; bind it as MODS + KEY", key)
	}
	if r.reported == nil {
		r.reported = map[string]bool{}
	}
	r.skipped = strList(plan.Value("skipped"))
	for _, key := range r.skipped {
		if id := render.KeyID(key); !r.reported[id] {
			r.logf("%s is bound by your %s config; skipping axiom's bind", key, r.configName)
			r.reported[id] = true
		}
	}
	r.applied = itemsOf(plan.Value("apply"))
	return r.applied
}

func (r *runtimeLayer) clear() {
	r.skipped = nil
	r.applied = nil
}

func itemsOf(v any) []any {
	if a, ok := v.(*jsonx.Array); ok {
		return a.Items
	}
	return nil
}
