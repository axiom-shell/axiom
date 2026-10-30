package dbus

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
)

// Method is one method an exported interface answers: its in and out
// signatures, and Fn, which returns the out values or an error (an
// *Error is sent as it is; any other as org.freedesktop.DBus.Error.Failed).
// Fn runs on the connection's one dispatch goroutine, so it must not
// block for long; ctx ends with the connection.
//
// A method whose answer waits on something (a person typing a password)
// sets Defer instead: it returns at once and calls reply later, from any
// goroutine, once (later calls are ignored). The call's descriptors are
// closed when Defer returns.
type Method struct {
	In, Out string
	Fn      func(ctx context.Context, call *Message) ([]any, error)
	Defer   func(ctx context.Context, call *Message, reply func(out []any, err error))
}

// Interface is an exported interface: its methods, and the signals it
// emits (name → signature, for introspection).
type Interface struct {
	Name    string
	Methods map[string]Method
	Signals map[string]string
}

const (
	ifaceIntrospectable = "org.freedesktop.DBus.Introspectable"
	ifacePeer           = "org.freedesktop.DBus.Peer"
)

// Export answers calls to iface at path until the returned func
// unexports it.
func (c *Conn) Export(path ObjectPath, iface Interface) (func(), error) {
	if !validPath(string(path)) {
		return nil, fmt.Errorf("dbus: %q is not an object path", path)
	}
	for name, m := range iface.Methods {
		if _, err := splitSignature(m.In); err != nil {
			return nil, fmt.Errorf("dbus: %s.%s: %w", iface.Name, name, err)
		}
		if _, err := splitSignature(m.Out); err != nil {
			return nil, fmt.Errorf("dbus: %s.%s: %w", iface.Name, name, err)
		}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.objects[path] == nil {
		c.objects[path] = map[string]*Interface{}
	}
	if _, taken := c.objects[path][iface.Name]; taken {
		return nil, fmt.Errorf("dbus: %s is already exported at %s", iface.Name, path)
	}
	p := &iface
	c.objects[path][iface.Name] = p
	return func() {
		c.mu.Lock()
		defer c.mu.Unlock()
		if c.objects[path][iface.Name] == p {
			delete(c.objects[path], iface.Name)
			if len(c.objects[path]) == 0 {
				delete(c.objects, path)
			}
		}
	}, nil
}

// dispatch runs incoming method calls one at a time.
func (c *Conn) dispatch() {
	defer c.wg.Done()
	for {
		select {
		case m := <-c.calls:
			c.handle(m)
		case <-c.done:
			return
		}
	}
}

func (c *Conn) handle(call *Message) {
	defer call.Close()
	switch call.Interface {
	case ifacePeer:
		switch call.Member {
		case "Ping":
			c.reply(call, "", nil)
		case "GetMachineId":
			id, err := os.ReadFile("/etc/machine-id")
			if err != nil {
				c.replyError(call, NewError(ErrFailed, "no machine id"))
				return
			}
			c.reply(call, "s", []any{strings.TrimSpace(string(id))})
		default:
			c.replyError(call, NewError(ErrUnknownMethod, "%s.%s", call.Interface, call.Member))
		}
		return
	case ifaceIntrospectable:
		if call.Member == "Introspect" {
			c.reply(call, "s", []any{c.introspect(call.Path)})
			return
		}
	}
	method, err := c.lookup(call)
	if err != nil {
		c.replyError(call, err)
		return
	}
	if string(call.Signature) != method.In {
		c.replyError(call, NewError(ErrInvalidArgs, "%s takes %q, not %q", call.Member, method.In, call.Signature))
		return
	}
	if method.Defer != nil {
		var once sync.Once
		method.Defer(c.ctx, call, func(out []any, err error) {
			once.Do(func() { c.answer(call, method.Out, out, err) })
		})
		return
	}
	out, ferr := method.Fn(c.ctx, call)
	c.answer(call, method.Out, out, ferr)
}

// answer replies to call with out, or with err (see Method).
func (c *Conn) answer(call *Message, sig string, out []any, err error) {
	if err != nil {
		var e *Error
		if !errors.As(err, &e) {
			e = NewError(ErrFailed, "%v", err)
		}
		c.replyError(call, e)
		return
	}
	c.reply(call, sig, out)
}

// lookup finds the method a call names; without an interface, the first
// exported interface at its path that has the member.
func (c *Conn) lookup(call *Message) (Method, *Error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ifaces := c.objects[call.Path]
	if len(ifaces) == 0 {
		return Method{}, NewError(ErrUnknownObject, "no object at %s", call.Path)
	}
	if call.Interface != "" {
		iface := ifaces[call.Interface]
		if iface == nil {
			return Method{}, NewError(ErrUnknownInterface, "%s has no interface %s", call.Path, call.Interface)
		}
		if m, ok := iface.Methods[call.Member]; ok {
			return m, nil
		}
		return Method{}, NewError(ErrUnknownMethod, "%s.%s", call.Interface, call.Member)
	}
	names := make([]string, 0, len(ifaces))
	for n := range ifaces {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		if m, ok := ifaces[n].Methods[call.Member]; ok {
			return m, nil
		}
	}
	return Method{}, NewError(ErrUnknownMethod, "no method %s at %s", call.Member, call.Path)
}

// introspect is the introspection XML of path: its interfaces, and the
// nodes under it that have objects.
func (c *Conn) introspect(path ObjectPath) string {
	c.mu.Lock()
	defer c.mu.Unlock()
	var b strings.Builder
	b.WriteString(`<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">` + "\n<node>\n")
	if ifaces := c.objects[path]; len(ifaces) > 0 {
		b.WriteString(`  <interface name="` + ifaceIntrospectable + `"><method name="Introspect"><arg type="s" direction="out"/></method></interface>` + "\n")
		b.WriteString(`  <interface name="` + ifacePeer + `"><method name="Ping"/><method name="GetMachineId"><arg type="s" direction="out"/></method></interface>` + "\n")
		names := make([]string, 0, len(ifaces))
		for n := range ifaces {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, n := range names {
			iface := ifaces[n]
			b.WriteString(`  <interface name="` + n + `">` + "\n")
			for _, m := range sortedKeys(iface.Methods) {
				b.WriteString(`    <method name="` + m + `">`)
				args := func(sig, dir string) {
					types, _ := splitSignature(sig)
					for _, t := range types {
						b.WriteString(`<arg type="` + t + `" direction="` + dir + `"/>`)
					}
				}
				args(iface.Methods[m].In, "in")
				args(iface.Methods[m].Out, "out")
				b.WriteString("</method>\n")
			}
			for _, s := range sortedKeys(iface.Signals) {
				b.WriteString(`    <signal name="` + s + `">`)
				types, _ := splitSignature(iface.Signals[s])
				for _, t := range types {
					b.WriteString(`<arg type="` + t + `"/>`)
				}
				b.WriteString("</signal>\n")
			}
			b.WriteString("  </interface>\n")
		}
	}
	prefix := string(path) + "/"
	if path == "/" {
		prefix = "/"
	}
	children := map[string]bool{}
	for p := range c.objects {
		if rest, ok := strings.CutPrefix(string(p), prefix); ok && rest != "" {
			child, _, _ := strings.Cut(rest, "/")
			children[child] = true
		}
	}
	for _, child := range sortedKeys(children) {
		b.WriteString(`  <node name="` + child + `"/>` + "\n")
	}
	b.WriteString("</node>\n")
	return b.String()
}

func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
