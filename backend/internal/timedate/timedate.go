// Package timedate reads and sets the machine's clock through
// systemd-timedated (org.freedesktop.timedate1): its time zone, whether
// network time is on and synchronized, and the time itself, for Settings ›
// System › Date & time. The setters ask polkit (the user's agent prompts),
// and Watch reports changes made anywhere (timedatectl, another desktop's
// settings). Docs: docs/dev/features/datetime.md.
package timedate

import (
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// timedated's names
const (
	BusName   = "org.freedesktop.timedate1"
	Path      = dbus.ObjectPath("/org/freedesktop/timedate1")
	Interface = "org.freedesktop.timedate1"
)

// How long a setter waits, polkit's prompt included
const setTimeout = 2 * time.Minute

// State is the clock as timedated says.
type State struct {
	Available       bool   `json:"available"` // timedated answered
	Timezone        string `json:"timezone"`  // "Europe/Berlin"; "" unset (UTC)
	LocalRTC        bool   `json:"localRtc"`  // the hardware clock keeps local time
	CanNTP          bool   `json:"canNtp"`    // a time sync service is installed
	NTP             bool   `json:"ntp"`       // it's on
	NTPSynchronized bool   `json:"ntpSynchronized"`
}

// Options configure a Clock.
type Options struct {
	// SystemBus dials the system bus
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	Log       *slog.Logger
}

// Clock talks to timedated.
type Clock struct{ o Options }

// New is a Clock.
func New(o Options) *Clock {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Clock{o: o}
}

// Get reads the state; without timedated (no systemd, no bus) it is
// {Available: false}, not an error.
func (c *Clock) Get(ctx context.Context) State {
	conn, err := c.o.SystemBus(ctx)
	if err != nil {
		return State{}
	}
	defer conn.Close()
	return read(ctx, conn)
}

func read(ctx context.Context, conn *dbus.Conn) State {
	props, err := conn.GetAll(ctx, BusName, Path, Interface)
	if err != nil {
		return State{}
	}
	st := State{Available: true}
	st.Timezone, _ = props["Timezone"].Value.(string)
	st.LocalRTC, _ = props["LocalRTC"].Value.(bool)
	st.CanNTP, _ = props["CanNTP"].Value.(bool)
	st.NTP, _ = props["NTP"].Value.(bool)
	st.NTPSynchronized, _ = props["NTPSynchronized"].Value.(bool)
	return st
}

// SetTimezone sets the time zone (an IANA name, as tz.zones lists them).
func (c *Clock) SetTimezone(ctx context.Context, zone string) error {
	if !validZone(zone) {
		return axerr.New(axerr.BadRequest, "%q is no time zone", zone)
	}
	return c.call(ctx, "SetTimezone", "sb", zone, true)
}

// SetNTP turns network time on or off.
func (c *Clock) SetNTP(ctx context.Context, on bool) error {
	return c.call(ctx, "SetNTP", "bb", on, true)
}

// SetTime sets the clock; timedated refuses while network time is on.
func (c *Clock) SetTime(ctx context.Context, at time.Time) error {
	if at.IsZero() {
		return axerr.New(axerr.BadRequest, "no time given")
	}
	return c.call(ctx, "SetTime", "xbb", at.UnixMicro(), false, true)
}

func (c *Clock) call(ctx context.Context, member, sig string, args ...any) error {
	ctx, cancel := context.WithTimeout(ctx, setTimeout)
	defer cancel()
	conn, err := c.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.CallInteractive(ctx, BusName, Path, Interface, member, sig, args...)
	return err
}

// Watch calls changed with the new state whenever timedated's properties
// change, until ctx ends; it returns when it can't (no bus), retrying
// being the caller's.
func (c *Clock) Watch(ctx context.Context, changed func(State)) error {
	conn, err := c.o.SystemBus(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	sub, err := conn.Subscribe(ctx, dbus.PropertiesChangedMatch(BusName, Path, Interface))
	if err != nil {
		return err
	}
	defer sub.Close()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-conn.Done():
			return conn.Err()
		case _, ok := <-sub.C:
			if !ok {
				return nil
			}
			// timedated's signals carry only what changed: read it whole
			changed(read(ctx, conn))
		}
	}
}

// validZone: an IANA name's shape ("Area/Location", "UTC"), never a path
// out of the zoneinfo folder.
func validZone(zone string) bool {
	if zone == "" || len(zone) > 128 || strings.HasPrefix(zone, "/") || strings.Contains(zone, "..") {
		return false
	}
	for _, r := range zone {
		if !(r >= 'A' && r <= 'Z' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || strings.ContainsRune("/_-+", r)) {
			return false
		}
	}
	return true
}
