package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/calendar"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
)

// calendarPart: CalendarManager's discovery of an account's calendars,
// answered by package calendar.
func (d *Daemon) calendarPart() part {
	return part{name: "calendar", methods: d.calendarMethods}
}

func (d *Daemon) calendarMethods(reg *rpc.Registry) {
	s := calendar.New(calendar.Options{})
	rpc.Handle(reg, "calendar.discover", func(ctx context.Context, c *rpc.Conn, p calendar.DiscoverRequest) (calendar.DiscoverResult, error) {
		return s.Discover(ctx, p)
	})
}
