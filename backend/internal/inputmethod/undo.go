package inputmethod

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/footprint"
)

// RegisterUndo makes l undo fcitx5's rows over D-Bus (a config's options, a
// group): each only while fcitx5 still holds what axiom set, and with no
// fcitx5 running the outcome is needsRunning and the row stays. (ibus's
// rows are gsettings keys, which the ledger undoes itself.)
func RegisterUndo(l *footprint.Ledger, bus func(ctx context.Context) (*dbus.Conn, error)) {
	u := &undoer{bus: bus}
	l.Register(footprint.KindFcitxConfig, u.config, u.checkConfig)
	l.Register(footprint.KindFcitxGroup, u.group, u.checkGroup)
}

type undoer struct {
	bus func(ctx context.Context) (*dbus.Conn, error)
}

// connect is a connection to the running fcitx5 (nil when none runs).
func (u *undoer) connect(ctx context.Context) (*fcitx, func()) {
	conn, err := u.bus(ctx)
	if err != nil {
		return nil, nil
	}
	if owner, _ := conn.NameOwner(ctx, fcitxName); owner == "" {
		conn.Close()
		return nil, nil
	}
	return &fcitx{conn: conn}, func() { conn.Close() }
}

// same says whether two trees hold the same values, a list or table with
// nothing in it counting as none.
func same(a, b any) bool {
	return reflect.DeepEqual(trim(a), trim(b))
}

func trim(v any) any {
	m, ok := v.(map[string]any)
	if !ok {
		return v
	}
	out := map[string]any{}
	for k, e := range m {
		if e = trim(e); e != nil {
			out[k] = e
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func (u *undoer) config(ctx context.Context, r *footprint.Row) (string, string) {
	f, closeConn := u.connect(ctx)
	if f == nil {
		return footprint.OutcomeNeedsRunning, "fcitx5 isn't running"
	}
	defer closeConn()
	var prior, wrote map[string]any
	_ = json.Unmarshal(r.Prior, &prior)
	_ = json.Unmarshal(r.Wrote, &wrote)
	current, err := f.getConfig(ctx, r.Target)
	if err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	if r.Wrote != nil && !same(pick(current, wrote), wrote) {
		return footprint.OutcomeChanged, "fcitx5's options were changed since: left as they are"
	}
	if len(prior) == 0 {
		return footprint.OutcomeGone, ""
	}
	if _, err := f.call(ctx, "SetConfig", "sv", r.Target, variantOf(prior)); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	return footprint.OutcomeDone, ""
}

func (u *undoer) checkConfig(ctx context.Context, r footprint.Row) string {
	f, closeConn := u.connect(ctx)
	if f == nil {
		return footprint.StatusPresent
	}
	defer closeConn()
	var wrote map[string]any
	_ = json.Unmarshal(r.Wrote, &wrote)
	if current, err := f.getConfig(ctx, r.Target); err == nil && r.Wrote != nil && !same(pick(current, wrote), wrote) {
		return footprint.StatusChanged
	}
	return footprint.StatusPresent
}

func (u *undoer) group(ctx context.Context, r *footprint.Row) (string, string) {
	f, closeConn := u.connect(ctx)
	if f == nil {
		return footprint.OutcomeNeedsRunning, "fcitx5 isn't running"
	}
	defer closeConn()
	name := strings.TrimPrefix(r.Target, "fcitx://group/")
	var prior, wrote groupRec
	_ = json.Unmarshal(r.Prior, &prior)
	_ = json.Unmarshal(r.Wrote, &wrote)
	current, err := f.group(ctx, name)
	if err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	if r.Wrote != nil && !reflect.DeepEqual(current, wrote) {
		return footprint.OutcomeChanged, "fcitx5's group was changed since: left as it is"
	}
	list := make([]any, 0, len(prior.Items))
	for _, it := range prior.Items {
		list = append(list, []any{it.Name, it.Layout})
	}
	if _, err := f.call(ctx, "SetInputMethodGroupInfo", "ssa(ss)", name, prior.Layout, list); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	if _, err := f.call(ctx, "Save"); err != nil {
		return footprint.OutcomeFailed, err.Error()
	}
	return footprint.OutcomeDone, ""
}

func (u *undoer) checkGroup(ctx context.Context, r footprint.Row) string {
	f, closeConn := u.connect(ctx)
	if f == nil {
		return footprint.StatusPresent
	}
	defer closeConn()
	var wrote groupRec
	_ = json.Unmarshal(r.Wrote, &wrote)
	if current, err := f.group(ctx, strings.TrimPrefix(r.Target, "fcitx://group/")); err == nil && r.Wrote != nil && !reflect.DeepEqual(current, wrote) {
		return footprint.StatusChanged
	}
	return footprint.StatusPresent
}
