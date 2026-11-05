package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/inputmethod"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// newInputMethod is the input method framework, fcitx5 or ibus
// (InputSourceManager): its state, switching, and the list axiom pushes.
func (d *Daemon) newInputMethod() {
	log := d.opts.Log.With("part", "inputmethod")
	d.inputMethod = inputmethod.New(inputmethod.Options{
		SessionBus: func(ctx context.Context) (*dbus.Conn, error) {
			addr, err := dbus.SessionAddress(d.opts.Getenv)
			if err != nil {
				return nil, err
			}
			return dbus.Dial(ctx, addr, dbus.Options{Log: log})
		},
		Getenv:    d.opts.Getenv,
		GSettings: gsettings,
		OnChange: func(st inputmethod.State) {
			if d.server != nil {
				pushInputMethodState.Send(d.server, st, subscribedTo(topicInputMethod))
			}
		},
		Log: log,
	})
}

// inputMethodPart: the input method framework, followed while the daemon
// runs.
func (d *Daemon) inputMethodPart() part {
	return part{
		name:    "inputmethod",
		methods: d.inputMethodMethods,
		run:     d.inputMethod.Run,
	}
}

func (d *Daemon) inputMethodMethods(reg *rpc.Registry) {
	type nameParams struct {
		Name string `json:"name"`
	}
	type pushParams struct {
		// The list's default xkb layout (fcitx5's group's; ibus has none)
		DefaultLayout string             `json:"defaultLayout"`
		Items         []inputmethod.Item `json:"items"`
	}
	// Only the shell changes what the framework keeps: it owns the list
	// (Input.keyboard.sources) and the settings
	refuse := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell changes the input method framework's settings")
		}
		return nil
	}
	rpc.Handle(reg, "inputMethod.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (inputmethod.State, error) {
		return d.inputMethod.State(), nil
	})
	rpc.Handle(reg, "inputMethod.set", func(ctx context.Context, c *rpc.Conn, p nameParams) (struct{}, error) {
		return struct{}{}, d.inputMethod.Set(ctx, p.Name)
	})
	rpc.Handle(reg, "inputMethod.push", func(ctx context.Context, c *rpc.Conn, p pushParams) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.inputMethod.Push(ctx, p.DefaultLayout, p.Items)
	})
	rpc.Handle(reg, "inputMethod.options", func(ctx context.Context, c *rpc.Conn, p inputmethod.Settings) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.inputMethod.Configure(ctx, p)
	})
	rpc.Handle(reg, "inputMethod.framework", func(ctx context.Context, c *rpc.Conn, p nameParams) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.inputMethod.SetFramework(p.Name)
	})
}
