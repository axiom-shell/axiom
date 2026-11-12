package daemon

import (
	"context"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
	sessx "github.com/axiom-shell/axiom/backend/internal/session"
	"github.com/axiom-shell/axiom/backend/internal/store"
)

// screenShareDone is screenshare.done: a request the shell shows is over.
type screenShareDone struct {
	ID string `json:"id"`
}

// How long the niri portal waits before trying the session bus again
const portalRetry = 5 * time.Second

// newScreenShare is the screen-share picker's broker (ScreenShareManager
// shows its requests).
func (d *Daemon) newScreenShare() {
	d.screenShare = screenshare.New(screenshare.Options{
		OnRequest: func(r screenshare.Request) bool {
			if d.server == nil || !slices.ContainsFunc(d.server.Conns(), shellIn(subscribedTo(topicScreenShare))) {
				return false
			}
			pushScreenShareRequest.Send(d.server, r, shellIn(subscribedTo(topicScreenShare)))
			return true
		},
		OnDone: func(id string) {
			if d.server != nil {
				pushScreenShareDone.Send(d.server, screenShareDone{ID: id}, shellIn(subscribedTo(topicScreenShare)))
			}
		},
		Log: d.opts.Log.With("part", "screenshare"),
	})
}

// screenSharePart: the picker, configured from the ScreenSharing section;
// under niri, axiom's ScreenCast portal on the session bus too.
func (d *Daemon) screenSharePart() part {
	configure := func() {
		cfg, _ := d.store.Config()
		v, _ := config.Lookup(cfg, config.Keys("ScreenSharing"))
		o, _ := v.(*jsonx.Object)
		if o == nil {
			d.screenShare.Configure(screenshare.Settings{})
			return
		}
		// reads: ScreenSharing.enabled, ScreenSharing.reuseFor, ScreenSharing.remember
		d.screenShare.Configure(screenshare.Settings{
			Enabled:  jsonx.Truthy(o.Value("enabled")),
			Reuse:    time.Duration(jsonx.ToNumber(o.Value("reuseFor"))) * time.Millisecond,
			Remember: jsonx.Truthy(o.Value("remember")),
		})
	}
	configure()
	return part{
		name:    "screenshare",
		methods: d.screenShareMethods,
		run: func(ctx context.Context) error {
			d.syncPortalLine(ctx, true)
			return d.runPortal(ctx)
		},
		onConfig: func(store.Event) {
			configure()
			d.tasks.Go(func(ctx context.Context) { d.syncPortalLine(ctx, false) })
		},
	}
}

// portalLineState is the niri portal line's state (screenShare.portalLine):
// the line `ScreenCast=axiom` in xdg-desktop-portal's niri-portals.conf is a
// session effect, added while ScreenSharing is on and taken out when axiom
// stops (session.PortalEnv).
type portalLineState struct {
	mu      sync.Mutex
	state   string
	err     string
	started bool
	want    bool
}

// portalLineResult is screenShare.portalLine's answer.
type portalLineResult struct {
	State string `json:"state"` // "on" | "off" | "link" | "missing" | "failed"
	Path  string `json:"path"`
	Line  string `json:"line"`
	Error string `json:"error"`
}

// syncPortalLine makes the line follow ScreenSharing.enabled, under niri
// only. initial: the daemon just started; a re-exec'd image (carried)
// adopts the record as it is, and only the next change edits the file. The
// portal is restarted only when the file changed and it runs.
func (d *Daemon) syncPortalLine(ctx context.Context, initial bool) {
	if ipc.NiriFromEnv(d.opts.Getenv) == nil {
		return
	}
	l := &d.portalLine
	l.mu.Lock()
	defer l.mu.Unlock()
	want := d.screenShare.Settings().Enabled
	if l.started && want == l.want && l.state != sessx.LineFailed {
		return
	}
	display := d.sessionScope().WaylandDisplay
	env := sessx.PortalEnvFrom(d.opts.Getenv)
	store := d.sessionStore()
	l.started, l.want = true, want
	if initial && d.carriedStart {
		// Adopted as it is: the record says whether the line is in
		l.state = sessx.LineOff
		if want && env.Has(store, display) {
			l.state = sessx.LineOn
		}
		return
	}
	state, changed, err := env.Sync(store, display, want)
	l.state, l.err = state, ""
	if err != nil {
		l.err = err.Error()
		d.opts.Log.Warn("screen share: the niri portal line", "state", state, "err", err)
	}
	if changed {
		d.opts.Log.Info("screen share: the niri portal line changed", "state", state)
		if err := d.restartPortal(ctx, nil); err != nil {
			d.opts.Log.Warn("screen share: restarting the portal", "err", err)
		}
	}
}

// runPortal serves the ScreenCast portal while niri runs, through session
// bus drops.
func (d *Daemon) runPortal(ctx context.Context) error {
	niri := ipc.NiriFromEnv(d.opts.Getenv)
	if niri == nil {
		return nil
	}
	log := d.opts.Log.With("part", "screenshare")
	portal := screenshare.NewPortal(screenshare.PortalOptions{
		Ask:      d.screenShare.Ask,
		Settings: d.screenShare.Settings,
		Sources: func(ctx context.Context) ([]screenshare.Output, []screenshare.Window, error) {
			outputs, err := niri.Outputs(ctx)
			if err != nil {
				return nil, nil, err
			}
			windows, err := niri.Windows(ctx)
			if err != nil {
				return nil, nil, err
			}
			outs := []screenshare.Output{}
			for _, o := range outputs {
				if !o.Disabled {
					outs = append(outs, screenshare.Output{Name: o.Name, Label: o.Description})
				}
			}
			wins := []screenshare.Window{}
			for _, w := range windows {
				id := strconv.FormatUint(w.ID, 10)
				wins = append(wins, screenshare.Window{Token: id, ID: id, Title: w.Title, AppID: w.AppID})
			}
			return outs, wins, nil
		},
		Log: log,
	})
	for {
		conn, err := d.sessionBus(ctx)
		if err == nil {
			err = portal.Run(ctx, conn)
			conn.Close()
		}
		if ctx.Err() != nil {
			return nil
		}
		log.Warn("screen share: the session bus is out of reach: retrying", "in", portalRetry, "err", err)
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(portalRetry):
		}
	}
}

// pickResult is screenshare.pick's: "picked" (with the choice and whether
// apps may keep it), "cancelled", or "off" (axiom's picker is off: the
// backend's own picks).
type pickResult struct {
	Status   string              `json:"status"`
	Choice   *screenshare.Choice `json:"choice,omitempty"`
	Remember bool                `json:"remember"`
}

func (d *Daemon) screenShareMethods(reg *rpc.Registry) {
	type pickParams struct {
		Backend string               `json:"backend"`
		Outputs []screenshare.Output `json:"outputs"`
		Windows []screenshare.Window `json:"windows"`
		Region  bool                 `json:"region"`
	}
	// `axiom screenshare-pick`, for xdg-desktop-portal-hyprland and -wlr:
	// waits for the user's choice, or the caller's end (the portal killed
	// it), which closes the picker
	rpc.Handle(reg, "screenshare.pick", func(ctx context.Context, c *rpc.Conn, p pickParams) (pickResult, error) {
		if p.Backend != screenshare.BackendXDPH && p.Backend != screenshare.BackendXDPW {
			return pickResult{}, axerr.New(axerr.BadRequest, "no such backend: %q", p.Backend)
		}
		settings := d.screenShare.Settings()
		if !settings.Enabled {
			return pickResult{Status: "off"}, nil
		}
		r := screenshare.Request{Backend: p.Backend, Outputs: p.Outputs, Windows: p.Windows, Region: p.Region}
		if r.Outputs == nil {
			r.Outputs = []screenshare.Output{}
		}
		if r.Windows == nil {
			r.Windows = []screenshare.Window{}
		}
		choice, err := d.screenShare.Ask(ctx, r)
		if err != nil {
			return pickResult{}, err
		}
		if choice == nil {
			return pickResult{Status: "cancelled"}, nil
		}
		return pickResult{Status: "picked", Choice: choice, Remember: settings.Remember}, nil
	})
	type answerParams struct {
		ID     string              `json:"id"`
		Choice *screenshare.Choice `json:"choice"`
		Cancel bool                `json:"cancel"`
	}
	rpc.Handle(reg, "screenShare.portalLine", func(ctx context.Context, c *rpc.Conn, _ struct{}) (portalLineResult, error) {
		l := &d.portalLine
		l.mu.Lock()
		defer l.mu.Unlock()
		state := l.state
		if state == "" {
			state = sessx.LineOff
		}
		return portalLineResult{State: state, Path: sessx.PortalEnvFrom(d.opts.Getenv).Path(), Line: sessx.PortalText, Error: l.err}, nil
	})
	rpc.Handle(reg, "screenshare.answer", func(ctx context.Context, c *rpc.Conn, p answerParams) (struct{}, error) {
		if !fromShell(c) {
			return struct{}{}, axerr.New(axerr.Refused, "only the shell answers a screen share request")
		}
		return struct{}{}, d.screenShare.Answer(p.ID, p.Choice, p.Cancel)
	})
}
