package daemon

import (
	"context"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/calendar"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// calendarPart: CalendarManager's calendars (discovery, syncs, saves and
// deletes), answered by package calendar in the user's state and data
// folders.
func (d *Daemon) calendarPart() part {
	return part{name: "calendar", methods: d.calendarMethods}
}

func (d *Daemon) calendarMethods(reg *rpc.Registry) {
	s := calendar.New(calendar.Options{
		StateDir: filepath.Join(d.dirs.State, "calendar"),
		DataDir:  d.dirs.Data,
		Secrets:  d.secretStore("calendar"),
		Log:      d.opts.Log.With("part", "calendar"),
	})
	rpc.Handle(reg, "calendar.discover", func(ctx context.Context, c *rpc.Conn, p calendar.DiscoverRequest) (calendar.DiscoverResult, error) {
		return s.Discover(ctx, p)
	})
	rpc.Handle(reg, "calendar.sync", func(ctx context.Context, c *rpc.Conn, p calendar.SyncRequest) (calendar.SyncResult, error) {
		return s.Sync(ctx, p)
	})
	rpc.Handle(reg, "calendar.save", func(ctx context.Context, c *rpc.Conn, p calendar.SaveRequest) (calendar.EditResult, error) {
		return s.Save(ctx, p)
	})
	rpc.Handle(reg, "calendar.delete", func(ctx context.Context, c *rpc.Conn, p calendar.EditRequest) (calendar.EditResult, error) {
		return s.Delete(ctx, p)
	})
}
