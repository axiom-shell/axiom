package dbus

import (
	"context"
	"fmt"
)

// The object manager interface: a service listing its objects at once
// and signalling the ones that come and go (UDisks2)
const IfaceObjectManager = "org.freedesktop.DBus.ObjectManager"

// Interfaces are an object's interfaces with their properties.
type Interfaces map[string]map[string]Variant

// ManagedObjects are a service's objects by path.
type ManagedObjects map[ObjectPath]Interfaces

// GetManagedObjects lists the objects the manager at path (dest's) holds.
func (c *Conn) GetManagedObjects(ctx context.Context, dest string, path ObjectPath) (ManagedObjects, error) {
	m, err := c.Call(ctx, dest, path, IfaceObjectManager, "GetManagedObjects", "")
	if err != nil {
		return nil, err
	}
	if m.Signature != "a{oa{sa{sv}}}" {
		return nil, fmt.Errorf("dbus: GetManagedObjects answered %q", m.Signature)
	}
	all, _ := m.Body[0].(map[any]any)
	out := ManagedObjects{}
	for k, v := range all {
		p, ok := k.(ObjectPath)
		if !ok {
			continue
		}
		out[p] = interfacesOf(v)
	}
	return out, nil
}

// interfacesOf reads an a{sa{sv}}.
func interfacesOf(v any) Interfaces {
	m, _ := v.(map[any]any)
	out := Interfaces{}
	for k, props := range m {
		name, ok := k.(string)
		if !ok {
			continue
		}
		p, _ := props.(map[string]Variant)
		if p == nil {
			p = map[string]Variant{}
		}
		out[name] = p
	}
	return out
}

// InterfacesAdded reads an InterfacesAdded signal: the object and the
// interfaces it gained, with their properties.
func InterfacesAdded(m *Message) (ObjectPath, Interfaces, error) {
	if m.Interface != IfaceObjectManager || m.Member != "InterfacesAdded" || m.Signature != "oa{sa{sv}}" {
		return "", nil, fmt.Errorf("dbus: not an InterfacesAdded signal")
	}
	p, _ := m.Body[0].(ObjectPath)
	return p, interfacesOf(m.Body[1]), nil
}

// InterfacesRemoved reads an InterfacesRemoved signal: the object and the
// interfaces it lost.
func InterfacesRemoved(m *Message) (ObjectPath, []string, error) {
	if m.Interface != IfaceObjectManager || m.Member != "InterfacesRemoved" || m.Signature != "oas" {
		return "", nil, fmt.Errorf("dbus: not an InterfacesRemoved signal")
	}
	var p ObjectPath
	var ifaces []string
	if err := m.Store(&p, &ifaces); err != nil {
		return "", nil, err
	}
	return p, ifaces, nil
}
