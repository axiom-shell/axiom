// Package filepicker shows the desktop's own file picker for a file or a
// folder (`filepicker.pick`, the shell's FilePickerManager):
// xdg-desktop-portal's FileChooser on the session bus, else zenity, else
// kdialog. Axiom draws no picker of its own.
package filepicker

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

const (
	portalName    = "org.freedesktop.portal.Desktop"
	portalPath    = dbus.ObjectPath("/org/freedesktop/portal/desktop")
	chooserIface  = "org.freedesktop.portal.FileChooser"
	requestIface  = "org.freedesktop.portal.Request"
	requestPrefix = "/org/freedesktop/portal/desktop/request/"
	// How long the bus and the portal get to show the picker; choosing in
	// it has no limit
	setupTimeout = 5 * time.Second
)

// Request is what to pick.
type Request struct {
	Title string `json:"title"`
	// The folder it opens in; one that doesn't exist opens home
	Start string `json:"start"`
	// A folder, not a file
	Folder bool `json:"folder,omitempty"`
	// "NAME:GLOB": offer only files matching GLOB, under NAME (a bare GLOB
	// is its own name). Files only.
	Filter string `json:"filter,omitempty"`
}

// Options are where the pickers come from.
type Options struct {
	// SessionBus connects to the session bus (nil: no portal)
	SessionBus func(ctx context.Context) (*dbus.Conn, error)
	// LookPath finds zenity and kdialog
	LookPath func(file string) (string, error)
	// Run runs a fallback picker and waits for it
	Run func(ctx context.Context, argv []string) (exitCode int, stdout string, err error)
	// Home is where a Start that doesn't exist opens
	Home string
	Log  *slog.Logger
}

// Pick shows a picker and waits for the user: the path chosen, "" when
// the picker was cancelled, an unavailable error when none could be shown.
func Pick(ctx context.Context, o Options, r Request) (string, error) {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	if info, err := os.Stat(r.Start); err != nil || !info.IsDir() {
		r.Start = o.Home
	}
	if o.SessionBus != nil {
		path, err := portal(ctx, o, r)
		if !errors.Is(err, errNoPortal) {
			return path, err
		}
		o.Log.Info("no portal file picker, trying zenity and kdialog", "err", err)
	}
	argv := fallbackCommand(o.LookPath, r)
	if argv == nil {
		return "", axerr.New(axerr.Unavailable, "no file picker: install xdg-desktop-portal with a FileChooser backend (xdg-desktop-portal-gtk or KDE's), zenity or kdialog")
	}
	code, stdout, err := o.Run(ctx, argv)
	if err != nil || code != 0 {
		return "", err
	}
	return strings.TrimSpace(stdout), nil
}

// errNoPortal: the portal couldn't show its picker, so a fallback may
var errNoPortal = errors.New("no portal file picker")

// portal asks the portal's FileChooser. Anything going wrong before it
// shows the picker wraps errNoPortal: no bus, no portal, no FileChooser
// backend (xdg-desktop-portal-hyprland has none), or, for a folder, one
// older than version 3, which ignores "directory" and would hand back a
// file.
func portal(ctx context.Context, o Options, r Request) (string, error) {
	setup, cancel := context.WithTimeout(ctx, setupTimeout)
	defer cancel()
	conn, err := o.SessionBus(setup)
	if err != nil {
		return "", fmt.Errorf("%w: %w", errNoPortal, err)
	}
	defer conn.Close()
	if r.Folder {
		v, err := conn.GetProperty(setup, portalName, portalPath, chooserIface, "version")
		if err != nil {
			return "", fmt.Errorf("%w: %w", errNoPortal, err)
		}
		if version, _ := v.Value.(uint32); version < 3 {
			return "", fmt.Errorf("%w: FileChooser version %d can't pick folders", errNoPortal, version)
		}
	}
	// Subscribed before the call, so a quick answer isn't missed; by
	// interface, not path, since a portal older than handle_token answers
	// on a path of its own
	sub, err := conn.Subscribe(setup, dbus.Match{Sender: portalName, Interface: requestIface, Member: "Response"})
	if err != nil {
		return "", fmt.Errorf("%w: %w", errNoPortal, err)
	}
	defer sub.Close()
	// Not cancelled with ctx: once sent, the portal may show the picker, so
	// a cancel arriving before the reply still needs its handle to close it
	opening, cancelOpen := context.WithTimeout(context.WithoutCancel(ctx), setupTimeout)
	defer cancelOpen()
	reply, err := conn.Call(opening, portalName, portalPath, chooserIface, "OpenFile", "ssa{sv}", "", r.Title, openOptions(r, rand.Text()))
	if err != nil {
		return "", fmt.Errorf("%w: %w", errNoPortal, err)
	}
	var handle dbus.ObjectPath
	if err := reply.Store(&handle); err != nil {
		return "", fmt.Errorf("%w: %w", errNoPortal, err)
	}
	for {
		select {
		case <-ctx.Done():
			// Nobody waits for the answer any more: close the picker
			closing, cancel := context.WithTimeout(context.Background(), time.Second)
			_, _ = conn.Call(closing, portalName, handle, requestIface, "Close", "")
			cancel()
			return "", axerr.Wrap(axerr.Unavailable, ctx.Err(), "the file picker was still open")
		case m, ok := <-sub.C:
			if !ok {
				return "", axerr.New(axerr.Unavailable, "the session bus closed with the file picker open")
			}
			if m.Path == handle {
				return response(m), nil
			}
		}
	}
}

// openOptions are OpenFile's options for r, its request named by token.
func openOptions(r Request, token string) map[string]dbus.Variant {
	options := map[string]dbus.Variant{
		"handle_token":   dbus.MakeVariant(token),
		"modal":          dbus.MakeVariant(true),
		"current_folder": dbus.MakeVariant(append([]byte(r.Start), 0)),
	}
	if r.Folder {
		options["directory"] = dbus.MakeVariant(true)
	} else if name, glob := filter(r); glob != "" {
		options["filters"] = dbus.Variant{Sig: "a(sa(us))", Value: []any{[]any{name, []any{[]any{uint32(0), glob}}}}}
	}
	return options
}

// response is the path a Request's Response chose, "" when it was
// cancelled or chose nothing.
func response(m *dbus.Message) string {
	var code uint32
	var results map[string]dbus.Variant
	if m.Store(&code, &results) != nil || code != 0 {
		return ""
	}
	uris, _ := results["uris"].Value.([]string)
	if len(uris) == 0 {
		return ""
	}
	u, err := url.Parse(uris[0])
	if err != nil {
		return ""
	}
	return u.Path
}

// filter is r's filter as its name and glob, both "" for none.
func filter(r Request) (name, glob string) {
	if r.Folder || r.Filter == "" {
		return "", ""
	}
	name, glob, _ = strings.Cut(r.Filter, ":")
	if glob == "" {
		glob = name
	}
	return name, glob
}

// fallbackCommand is zenity's or kdialog's command for r, nil with
// neither installed.
func fallbackCommand(lookPath func(string) (string, error), r Request) []string {
	name, glob := filter(r)
	if _, err := lookPath("zenity"); err == nil {
		argv := []string{"zenity", "--file-selection", "--title", r.Title, "--filename", r.Start + "/"}
		if r.Folder {
			return append(argv, "--directory")
		}
		if glob != "" {
			argv = append(argv, "--file-filter", name+" | "+glob)
		}
		return argv
	}
	if _, err := lookPath("kdialog"); err == nil {
		if r.Folder {
			return []string{"kdialog", "--title", r.Title, "--getexistingdirectory", r.Start}
		}
		argv := []string{"kdialog", "--title", r.Title, "--getopenfilename", r.Start}
		if glob != "" {
			argv = append(argv, glob)
		}
		return argv
	}
	return nil
}
