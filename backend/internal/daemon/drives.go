package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/udisks"
)

// newDrives is UDisks2's removable drives on the system bus
// (DrivesManager): their state, and an event when one is plugged in or
// pulled out.
func (d *Daemon) newDrives() {
	log := d.opts.Log.With("part", "drives")
	d.drives = udisks.New(udisks.Options{
		SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
			return dbus.Dial(ctx, dbus.SystemAddress(d.opts.Getenv), dbus.Options{Log: log})
		},
		// The dev fixtures (scripts/dev/drive-fixtures.sh) are loop devices
		IncludeLoop: d.opts.Getenv("AXIOM_DRIVES_INCLUDE_LOOP") == "1",
		OnChange: func(st udisks.State) {
			if d.server != nil {
				pushDrivesState.Send(d.server, st, subscribedTo(topicDrives))
			}
		},
		OnEvent: func(e udisks.Event) {
			if d.server != nil {
				pushDrivesEvent.Send(d.server, e, subscribedTo(topicDrives))
			}
		},
		Log: log,
	})
}

// drivesPart: the removable drives, followed while the daemon runs.
func (d *Daemon) drivesPart() part {
	return part{
		name:    "drives",
		methods: d.drivesMethods,
		run:     d.drives.Run,
	}
}

func (d *Daemon) drivesMethods(reg *rpc.Registry) {
	type idParams struct {
		ID string `json:"id"`
	}
	type unlockParams struct {
		ID         string `json:"id"`
		Passphrase string `json:"passphrase"`
	}
	type mountResult struct {
		MountPoint string `json:"mountPoint"`
	}
	type unlockResult struct {
		CleartextID string `json:"cleartextId"`
		// There's a filesystem in it to mount (not LVM, nor nothing yet)
		Mountable bool `json:"mountable"`
	}
	// Only the shell mounts, unlocks or ejects: it's the one showing them
	refuse := func(c *rpc.Conn) error {
		if !fromShell(c) {
			return axerr.New(axerr.Refused, "only the shell changes drives")
		}
		return nil
	}
	rpc.Handle(reg, "drives.get", func(ctx context.Context, c *rpc.Conn, _ struct{}) (udisks.State, error) {
		return d.drives.State(), nil
	})
	rpc.Handle(reg, "drives.mount", func(ctx context.Context, c *rpc.Conn, p idParams) (mountResult, error) {
		if err := refuse(c); err != nil {
			return mountResult{}, err
		}
		at, err := d.drives.Mount(ctx, p.ID)
		return mountResult{MountPoint: at}, err
	})
	rpc.Handle(reg, "drives.unmount", func(ctx context.Context, c *rpc.Conn, p idParams) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.drives.Unmount(ctx, p.ID)
	})
	rpc.Handle(reg, "drives.unlock", func(ctx context.Context, c *rpc.Conn, p unlockParams) (unlockResult, error) {
		if err := refuse(c); err != nil {
			return unlockResult{}, err
		}
		v, err := d.drives.Unlock(ctx, p.ID, p.Passphrase)
		return unlockResult{CleartextID: v.CleartextID, Mountable: v.Mountable}, err
	})
	rpc.Handle(reg, "drives.lock", func(ctx context.Context, c *rpc.Conn, p idParams) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.drives.Lock(ctx, p.ID)
	})
	rpc.Handle(reg, "drives.eject", func(ctx context.Context, c *rpc.Conn, p idParams) (struct{}, error) {
		if err := refuse(c); err != nil {
			return struct{}{}, err
		}
		return struct{}{}, d.drives.Eject(ctx, p.ID)
	})
}
