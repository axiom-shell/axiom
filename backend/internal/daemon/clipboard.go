package daemon

import (
	"context"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/clipboard"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/store"
	"github.com/axiom-shell/axiom/backend/internal/wayland/datacontrol"
)

// clipboardState is clipboard.state: the history, newest first.
type clipboardState struct {
	Entries []clipboard.Entry `json:"entries"`
}

// newClipboard is the clipboard on the connection's data control, and its
// history (Launcher.providers.clipboard).
func (d *Daemon) newClipboard() {
	log := d.opts.Log.With("part", "clipboard")
	d.clipboard = clipboard.New(clipboard.Options{
		Dir: filepath.Join(d.opts.Getenv("XDG_RUNTIME_DIR"), "axiom", "clipboard"),
		Set: func(mimes []string, data map[string][]byte) error { return d.clip.Set(mimes, data) },
		Current: func() clipboard.Offer {
			// A nil *Offer isn't a nil Offer
			if o := d.clip.Current(); o != nil {
				return o
			}
			return nil
		},
		OnChange: func() {
			if d.server != nil {
				pushClipboardState.Send(d.server, clipboardState{Entries: d.clipboard.Entries()}, subscribedTo(topicClipboard))
			}
		},
		Log: log,
	})
	d.clip = datacontrol.New(datacontrol.Options{
		Seat: d.seat,
		Log:  log,
		OnSelection: func(o *datacontrol.Offer) {
			if o != nil {
				d.clipboard.Selected(o)
			}
		},
		OnChange: d.pushWayland,
		Go:       d.tasks.Go,
	})
}

// clipboardPart: the history, recording while the launcher's clipboard
// provider is on.
func (d *Daemon) clipboardPart() part {
	configure := func() {
		cfg, _ := d.store.Config()
		v, _ := config.Lookup(cfg, config.Keys("Launcher", "providers", "clipboard"))
		o, _ := v.(*jsonx.Object)
		if o == nil {
			d.clipboard.Configure(false, 0)
			return
		}
		// reads: Launcher.providers.clipboard.enabled, Launcher.providers.clipboard.maxEntries
		d.clipboard.Configure(jsonx.Truthy(o.Value("enabled")), int(jsonx.ToNumber(o.Value("maxEntries"))))
	}
	configure()
	return part{
		name:     "clipboard",
		methods:  d.clipboardMethods,
		run:      d.clipboard.Run,
		onConfig: func(store.Event) { configure() },
	}
}

func (d *Daemon) clipboardMethods(reg *rpc.Registry) {
	// What was copied is the user's: only the shell reads or changes it
	shellOnly := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell reaches the clipboard")
		}
		return nil
	}
	type idParams struct {
		ID string `json:"id"`
	}
	rpc.Handle(reg, "clipboard.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (clipboardState, error) {
		if err := shellOnly(c); err != nil {
			return clipboardState{}, err
		}
		return clipboardState{Entries: d.clipboard.Entries()}, nil
	})
	type copyParams struct {
		ID   string  `json:"id"`
		Text *string `json:"text"`
		Path string  `json:"path"`
		Mime string  `json:"mime"`
	}
	rpc.Handle(reg, "clipboard.copy", func(ctx context.Context, c *rpc.Conn, p copyParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		switch {
		case p.Text != nil:
			return struct{}{}, d.clipboard.CopyText(*p.Text)
		case p.Path != "":
			if p.Mime == "" {
				return struct{}{}, axerr.New(axerr.BadRequest, "a file is copied with its mime type")
			}
			return struct{}{}, d.clipboard.CopyFile(p.Path, p.Mime)
		case p.ID != "":
			return struct{}{}, d.clipboard.Copy(p.ID)
		}
		return struct{}{}, axerr.New(axerr.BadRequest, "copy an id, a text or a file")
	})
	type textResult struct {
		Text string `json:"text"`
	}
	rpc.Handle(reg, "clipboard.text", func(ctx context.Context, c *rpc.Conn, p idParams) (textResult, error) {
		if err := shellOnly(c); err != nil {
			return textResult{}, err
		}
		text, err := d.clipboard.Text(p.ID)
		return textResult{Text: text}, err
	})
	rpc.Handle(reg, "clipboard.remove", func(ctx context.Context, c *rpc.Conn, p idParams) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		d.clipboard.Remove(p.ID)
		return struct{}{}, nil
	})
	rpc.Handle(reg, "clipboard.clear", func(ctx context.Context, c *rpc.Conn, _ struct{}) (struct{}, error) {
		if err := shellOnly(c); err != nil {
			return struct{}{}, err
		}
		d.clipboard.Clear()
		return struct{}{}, nil
	})
	type typesResult struct {
		Mimes []string `json:"mimes"`
	}
	rpc.Handle(reg, "clipboard.types", func(ctx context.Context, c *rpc.Conn, _ struct{}) (typesResult, error) {
		if err := shellOnly(c); err != nil {
			return typesResult{}, err
		}
		return typesResult{Mimes: append([]string{}, d.clipboard.Types()...)}, nil
	})
	type saveParams struct {
		Mimes []string `json:"mimes"`
		Path  string   `json:"path"`
	}
	type saveResult struct {
		Mime string `json:"mime"`
	}
	rpc.Handle(reg, "clipboard.save", func(ctx context.Context, c *rpc.Conn, p saveParams) (saveResult, error) {
		if err := shellOnly(c); err != nil {
			return saveResult{}, err
		}
		if !filepath.IsAbs(p.Path) {
			return saveResult{}, axerr.New(axerr.BadRequest, "save to an absolute path")
		}
		mime, err := d.clipboard.Save(ctx, p.Mimes, p.Path)
		return saveResult{Mime: mime}, err
	})
}
