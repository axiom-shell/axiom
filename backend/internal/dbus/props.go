package dbus

import (
	"context"
	"fmt"
)

// The properties interface
const ifaceProperties = "org.freedesktop.DBus.Properties"

// GetProperty reads one property.
func (c *Conn) GetProperty(ctx context.Context, dest string, path ObjectPath, iface, name string) (Variant, error) {
	m, err := c.Call(ctx, dest, path, ifaceProperties, "Get", "ss", iface, name)
	if err != nil {
		return Variant{}, err
	}
	var v Variant
	return v, m.Store(&v)
}

// GetAll reads every property of an interface.
func (c *Conn) GetAll(ctx context.Context, dest string, path ObjectPath, iface string) (map[string]Variant, error) {
	m, err := c.Call(ctx, dest, path, ifaceProperties, "GetAll", "s", iface)
	if err != nil {
		return nil, err
	}
	var props map[string]Variant
	return props, m.Store(&props)
}

// PropertiesChangedMatch selects the PropertiesChanged signals of the
// object at path, from sender.
func PropertiesChangedMatch(sender string, path ObjectPath, iface string) Match {
	return Match{Sender: sender, Path: path, Interface: ifaceProperties, Member: "PropertiesChanged", Arg0: iface}
}

// PropertiesChanged reads a PropertiesChanged signal: the interface, the
// properties changed with their values, and those changed without.
func PropertiesChanged(m *Message) (iface string, changed map[string]Variant, invalidated []string, err error) {
	if m.Interface != ifaceProperties || m.Member != "PropertiesChanged" || m.Signature != "sa{sv}as" {
		return "", nil, nil, fmt.Errorf("dbus: not a PropertiesChanged signal")
	}
	err = m.Store(&iface, &changed, &invalidated)
	return
}
