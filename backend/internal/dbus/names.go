package dbus

import (
	"context"
)

// RequestName flags
const (
	NameAllowReplacement uint32 = 0x1
	NameReplaceExisting  uint32 = 0x2
	NameDoNotQueue       uint32 = 0x4
)

// RequestName replies
const (
	NamePrimaryOwner uint32 = 1
	NameInQueue      uint32 = 2
	NameExists       uint32 = 3
	NameAlreadyOwner uint32 = 4
)

// RequestName asks the bus for a well-known name; the reply says whether
// this connection now owns it (NamePrimaryOwner, NameAlreadyOwner).
func (c *Conn) RequestName(ctx context.Context, name string, flags uint32) (uint32, error) {
	m, err := c.Call(ctx, BusName, BusPath, BusInterface, "RequestName", "su", name, flags)
	if err != nil {
		return 0, err
	}
	var reply uint32
	return reply, m.Store(&reply)
}

// ReleaseName gives a name back.
func (c *Conn) ReleaseName(ctx context.Context, name string) error {
	_, err := c.Call(ctx, BusName, BusPath, BusInterface, "ReleaseName", "s", name)
	return err
}

// NameOwner is the unique name owning name; an error wrapping
// ErrNameHasNoOwner when none does.
func (c *Conn) NameOwner(ctx context.Context, name string) (string, error) {
	m, err := c.Call(ctx, BusName, BusPath, BusInterface, "GetNameOwner", "s", name)
	if err != nil {
		return "", err
	}
	var owner string
	return owner, m.Store(&owner)
}

// ConnectionPID is the process id behind a connection on the bus.
func (c *Conn) ConnectionPID(ctx context.Context, name string) (uint32, error) {
	m, err := c.Call(ctx, BusName, BusPath, BusInterface, "GetConnectionUnixProcessID", "s", name)
	if err != nil {
		return 0, err
	}
	var pid uint32
	return pid, m.Store(&pid)
}

// NameOwnerChanged selects the bus's signal for name changing owner (all
// names when name is ""): its body is name, old owner, new owner, ""
// for none.
func NameOwnerChanged(name string) Match {
	return Match{Sender: BusName, Path: BusPath, Interface: BusInterface, Member: "NameOwnerChanged", Arg0: name}
}
