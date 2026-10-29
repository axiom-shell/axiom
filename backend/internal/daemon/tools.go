package daemon

import (
	"context"
	"os/exec"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/community"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/deps"
	"github.com/axiom-shell/axiom/backend/internal/filepicker"
	"github.com/axiom-shell/axiom/backend/internal/media"
	"github.com/axiom-shell/axiom/backend/internal/netif"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/sysmon"
	"github.com/axiom-shell/axiom/backend/internal/tz"
)

// toolsPart: one-off lookups the shell asks for, each answered from the
// package owning it.
func (d *Daemon) toolsPart() part {
	return part{name: "tools", methods: d.toolsMethods}
}

func (d *Daemon) toolsMethods(reg *rpc.Registry) {
	lookupMethods(reg, d.opts.Getenv)
	type checkParams struct {
		Commands []string `json:"commands"`
	}
	type checkResult struct {
		Found []string `json:"found"`
	}
	rpc.Handle(reg, "deps.check", func(ctx context.Context, c *rpc.Conn, p checkParams) (checkResult, error) {
		return checkResult{Found: append([]string{}, deps.Check(p.Commands, deps.Options{})...)}, nil
	})
	type killParams struct {
		PID int `json:"pid"`
	}
	rpc.Handle(reg, "system.kill", func(ctx context.Context, c *rpc.Conn, p killParams) (struct{}, error) {
		return struct{}{}, sysmon.Kill(p.PID)
	})
	type artParams struct {
		URL  string `json:"url"`
		Path string `json:"path"` // in $XDG_RUNTIME_DIR/axiom/media-art/
	}
	type artResult struct {
		Path string `json:"path"`
	}
	rpc.Handle(reg, "media.art", func(ctx context.Context, c *rpc.Conn, p artParams) (artResult, error) {
		o := media.Options{Dir: media.ArtDir(d.opts.Getenv("XDG_RUNTIME_DIR"))}
		return artResult{Path: p.Path}, media.Art(ctx, o, p.URL, p.Path)
	})
	// The community gallery's files, only into its cache, its palettes'
	// folder and the wallpapers a setup brings
	fetcher := community.New(community.Options{Roots: []string{
		d.dirs.Cache + "community/", d.dirs.CommunityThemes, d.dirs.Data + "wallpapers/",
	}})
	type fetchParams struct {
		Files []community.File `json:"files"`
	}
	type fetchResult struct {
		Files []community.Result `json:"files"`
	}
	rpc.Handle(reg, "community.fetch", func(ctx context.Context, c *rpc.Conn, p fetchParams) (fetchResult, error) {
		return fetchResult{Files: fetcher.Fetch(ctx, p.Files)}, nil
	})
	type pickResult struct {
		Path string `json:"path"` // "": cancelled
	}
	// Waits for the user: the answer comes when the picker closes
	rpc.Handle(reg, "filepicker.pick", func(ctx context.Context, c *rpc.Conn, p filepicker.Request) (pickResult, error) {
		path, err := filepicker.Pick(ctx, d.filePickerOptions(), p)
		return pickResult{Path: path}, err
	})
}

// filePickerOptions: the portal on the session bus; zenity and kdialog
// run as the shell's commands do (its environment, handed on across a
// re-exec)
func (d *Daemon) filePickerOptions() filepicker.Options {
	log := d.opts.Log.With("part", "filepicker")
	return filepicker.Options{
		SessionBus: func(ctx context.Context) (*dbus.Conn, error) {
			addr, err := dbus.SessionAddress(d.opts.Getenv)
			if err != nil {
				return nil, err
			}
			return dbus.Dial(ctx, addr, dbus.Options{Log: log})
		},
		LookPath: exec.LookPath,
		Run: func(ctx context.Context, argv []string) (int, string, error) {
			res, err := command.Run(ctx, d.commandOptions(), argv, nil)
			return res.ExitCode, res.Stdout, err
		},
		Home: d.opts.Getenv("HOME"),
		Log:  log,
	}
}

// lookupMethods are the lookups the greeter's axiom answers too (its
// clocks' zones, the Network module's address).
func lookupMethods(reg *rpc.Registry, getenv func(string) string) {
	type zonesResult struct {
		Zones []string `json:"zones"`
	}
	rpc.Handle(reg, "tz.zones", func(ctx context.Context, c *rpc.Conn, _ struct{}) (zonesResult, error) {
		return zonesResult{Zones: append([]string{}, tz.Zones(tz.Dir(getenv))...)}, nil
	})
	type offsetsParams struct {
		Zones []string `json:"zones"`
	}
	type offsetsResult struct {
		Offsets map[string]int `json:"offsets"` // minutes east of UTC
	}
	rpc.Handle(reg, "tz.offsets", func(ctx context.Context, c *rpc.Conn, p offsetsParams) (offsetsResult, error) {
		return offsetsResult{Offsets: tz.Offsets(tz.Dir(getenv), p.Zones, time.Now())}, nil
	})
	type addressesParams struct {
		Device string `json:"device"`
	}
	type addressesResult struct {
		IPv4 string `json:"ipv4"` // "" for none
	}
	rpc.Handle(reg, "net.addresses", func(ctx context.Context, c *rpc.Conn, p addressesParams) (addressesResult, error) {
		return addressesResult{IPv4: netif.IPv4(p.Device)}, nil
	})
}
