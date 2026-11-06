package screenshare

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

// Portal is axiom's org.freedesktop.impl.portal.ScreenCast for niri, which
// the user's niri-portals.conf points xdg-desktop-portal at. Its picker
// is the Broker's; niri casts what was picked through its
// org.gnome.Mutter.ScreenCast (niri makes the PipeWire stream; the
// frontend hands it to the app). With axiom's picker off, every call goes
// on to xdg-desktop-portal-gnome, as if it answered.
type Portal struct {
	o PortalOptions

	mu       sync.Mutex
	sessions map[dbus.ObjectPath]*castSession
}

// PortalOptions configure a Portal.
type PortalOptions struct {
	// Ask asks the user (Broker.Ask)
	Ask func(context.Context, Request) (*Choice, error)
	// Settings are the ScreenSharing section's
	Settings func() Settings
	// Sources are what can be shared now: niri's outputs and windows
	Sources func(context.Context) ([]Output, []Window, error)
	Log     *slog.Logger
}

// The portal's names
const (
	PortalBusName   = "org.freedesktop.impl.portal.desktop.axiom"
	portalPath      = dbus.ObjectPath("/org/freedesktop/portal/desktop")
	ifaceScreenCast = "org.freedesktop.impl.portal.ScreenCast"
	ifaceRequest    = "org.freedesktop.impl.portal.Request"
	ifaceSession    = "org.freedesktop.impl.portal.Session"
	ifaceProps      = "org.freedesktop.DBus.Properties"
	// xdg-desktop-portal-gnome, which a session goes on to with the
	// picker off
	gnomeBusName = "org.freedesktop.impl.portal.desktop.gnome"
	// niri's casting
	mutterBusName = "org.gnome.Mutter.ScreenCast"
	mutterPath    = dbus.ObjectPath("/org/gnome/Mutter/ScreenCast")
	ifaceMutter   = "org.gnome.Mutter.ScreenCast"
	ifaceMSession = "org.gnome.Mutter.ScreenCast.Session"
	ifaceMStream  = "org.gnome.Mutter.ScreenCast.Stream"
)

// The portal's source types and cursor modes (bit flags), its version, and
// its responses
const (
	sourceMonitor  uint32 = 1
	sourceWindow   uint32 = 2
	cursorHidden   uint32 = 1
	cursorEmbedded uint32 = 2
	cursorMetadata uint32 = 4
	portalVersion  uint32 = 4

	responseOK        uint32 = 0
	responseCancelled uint32 = 1
	responseOther     uint32 = 2
)

// The restore data's vendor and version (restore_data (suv))
const (
	restoreVendor         = "axiom"
	restoreVersion uint32 = 1
)

// How long niri may take to make a stream after Start
const streamTimeout = 10 * time.Second

// castSession is one ScreenCast session.
type castSession struct {
	handle  dbus.ObjectPath
	appID   string
	forward bool
	// SelectSources' options and the choice
	types   uint32
	cursor  uint32
	persist uint32
	choice  *Choice
	// What was picked, as restore data keeps it
	picked map[string]dbus.Variant
	// niri's session, once started
	mutter   dbus.ObjectPath
	unexport func()
}

// NewPortal returns a portal; Run serves it.
func NewPortal(o PortalOptions) *Portal {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Portal{o: o, sessions: map[dbus.ObjectPath]*castSession{}}
}

// Run serves the portal on conn until ctx ends or the connection does.
// When another program holds the name, it waits for it to come free.
func (p *Portal) Run(ctx context.Context, conn *dbus.Conn) error {
	// The calls still answering (a pick waiting for a person) end with it
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	unexport, err := conn.Export(portalPath, dbus.Interface{Name: ifaceScreenCast, Methods: p.methods(ctx, conn)})
	if err != nil {
		return err
	}
	defer unexport()
	unexportProps, err := conn.Export(portalPath, dbus.Interface{Name: ifaceProps, Methods: p.props()})
	if err != nil {
		return err
	}
	defer unexportProps()
	names, err := conn.Subscribe(ctx, dbus.NameOwnerChanged(PortalBusName))
	if err != nil {
		return err
	}
	defer names.Close()
	// niri ending a cast (its window closed, its output went away)
	closed, err := conn.Subscribe(ctx, dbus.Match{Interface: ifaceMSession, Member: "Closed"})
	if err != nil {
		return err
	}
	defer closed.Close()
	// xdg-desktop-portal-gnome ending a session relayed to it
	gnomeClosed, err := conn.Subscribe(ctx, dbus.Match{Sender: gnomeBusName, Interface: ifaceSession, Member: "Closed"})
	if err != nil {
		return err
	}
	defer gnomeClosed.Close()
	defer p.closeAll(conn)
	p.take(ctx, conn)
	for {
		select {
		case <-ctx.Done():
			if conn.Err() == nil {
				release, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				conn.ReleaseName(release, PortalBusName)
				cancel()
			}
			return nil
		case m, ok := <-names.C:
			if !ok {
				return conn.Err()
			}
			var name, old, new string
			if m.Store(&name, &old, &new) == nil && new == "" {
				p.take(ctx, conn)
			}
		case m, ok := <-closed.C:
			if !ok {
				return conn.Err()
			}
			p.ended(conn, func(s *castSession) bool { return s.mutter == m.Path })
		case m, ok := <-gnomeClosed.C:
			if !ok {
				return conn.Err()
			}
			p.ended(conn, func(s *castSession) bool { return s.forward && s.handle == m.Path })
		}
	}
}

// take asks for the name.
func (p *Portal) take(ctx context.Context, conn *dbus.Conn) {
	reply, err := conn.RequestName(ctx, PortalBusName, dbus.NameDoNotQueue)
	switch {
	case err != nil:
		p.o.Log.Warn("asking for "+PortalBusName, "err", err)
	case reply != dbus.NamePrimaryOwner && reply != dbus.NameAlreadyOwner:
		p.o.Log.Info(PortalBusName + " is held by another program: waiting for it")
	}
}

func (p *Portal) props() map[string]dbus.Method {
	all := func() map[string]dbus.Variant {
		return map[string]dbus.Variant{
			"AvailableSourceTypes": dbus.MakeVariant(sourceMonitor | sourceWindow),
			"AvailableCursorModes": dbus.MakeVariant(cursorHidden | cursorEmbedded),
			"version":              dbus.MakeVariant(portalVersion),
		}
	}
	return map[string]dbus.Method{
		"Get": {In: "ss", Out: "v", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var iface, name string
			if err := m.Store(&iface, &name); err != nil {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
			}
			v, ok := all()[name]
			if iface != ifaceScreenCast || !ok {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "no property %s.%s", iface, name)
			}
			return []any{v}, nil
		}},
		"GetAll": {In: "s", Out: "a{sv}", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			var iface string
			if err := m.Store(&iface); err != nil {
				return nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err)
			}
			if iface != ifaceScreenCast {
				return []any{map[string]dbus.Variant{}}, nil
			}
			return []any{all()}, nil
		}},
		"Set": {In: "ssv", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			return nil, dbus.NewError("org.freedesktop.DBus.Error.PropertyReadOnly", "the properties are read-only")
		}},
	}
}

// call is a portal method call's arguments.
type call struct {
	handle, session dbus.ObjectPath
	appID           string
	options         map[string]dbus.Variant
	// body is the call's arguments as they came, to relay
	sig  string
	body []any
}

func (p *Portal) methods(ctx context.Context, conn *dbus.Conn) map[string]dbus.Method {
	// Each answers on a goroutine of its own: a pick waits for a person
	deferred := func(in string, fn func(context.Context, call) (uint32, map[string]dbus.Variant)) dbus.Method {
		return dbus.Method{In: in, Out: "ua{sv}", Defer: func(_ context.Context, m *dbus.Message, reply func([]any, error)) {
			c := call{sig: string(m.Signature), body: m.Body}
			var err error
			if in == "oossa{sv}" {
				var parent string
				err = m.Store(&c.handle, &c.session, &c.appID, &parent, &c.options)
			} else {
				err = m.Store(&c.handle, &c.session, &c.appID, &c.options)
			}
			if err != nil {
				reply(nil, dbus.NewError(dbus.ErrInvalidArgs, "%v", err))
				return
			}
			go func() {
				code, results := fn(ctx, c)
				if results == nil {
					results = map[string]dbus.Variant{}
				}
				reply([]any{code, results}, nil)
			}()
		}}
	}
	return map[string]dbus.Method{
		"CreateSession": deferred("oosa{sv}", func(ctx context.Context, c call) (uint32, map[string]dbus.Variant) {
			return p.createSession(ctx, conn, c)
		}),
		"SelectSources": deferred("oosa{sv}", func(ctx context.Context, c call) (uint32, map[string]dbus.Variant) {
			return p.selectSources(ctx, conn, c)
		}),
		"Start": deferred("oossa{sv}", func(ctx context.Context, c call) (uint32, map[string]dbus.Variant) {
			return p.start(ctx, conn, c)
		}),
	}
}

// request runs fn with the call's Request exported at its handle: the
// frontend's Close ends fn's context (and is relayed when forwarded).
func (p *Portal) request(ctx context.Context, conn *dbus.Conn, c call, forward bool, fn func(context.Context) (uint32, map[string]dbus.Variant)) (uint32, map[string]dbus.Variant) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	unexport, err := conn.Export(c.handle, dbus.Interface{Name: ifaceRequest, Methods: map[string]dbus.Method{
		"Close": {Fn: func(context.Context, *dbus.Message) ([]any, error) {
			if forward {
				relay, done := context.WithTimeout(context.Background(), 2*time.Second)
				conn.Call(relay, gnomeBusName, c.handle, ifaceRequest, "Close", "")
				done()
			}
			cancel()
			return nil, nil
		}},
	}})
	if err == nil {
		defer unexport()
	}
	return fn(ctx)
}

// relay passes the call on to xdg-desktop-portal-gnome, and its answer
// back.
func relay(ctx context.Context, conn *dbus.Conn, member string, c call) (uint32, map[string]dbus.Variant) {
	m, err := conn.Call(ctx, gnomeBusName, portalPath, ifaceScreenCast, member, c.sig, c.body...)
	if err != nil {
		return responseOther, nil
	}
	defer m.Close()
	var code uint32
	var results map[string]dbus.Variant
	if m.Store(&code, &results) != nil {
		return responseOther, nil
	}
	return code, results
}

func (p *Portal) session(path dbus.ObjectPath) *castSession {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.sessions[path]
}

func (p *Portal) createSession(ctx context.Context, conn *dbus.Conn, c call) (uint32, map[string]dbus.Variant) {
	if p.session(c.session) != nil {
		return responseOther, nil
	}
	s := &castSession{handle: c.session, appID: c.appID, forward: !p.o.Settings().Enabled}
	unexport, err := conn.Export(c.session, dbus.Interface{
		Name:    ifaceSession,
		Methods: map[string]dbus.Method{"Close": {Fn: func(context.Context, *dbus.Message) ([]any, error) { p.close(conn, s, false); return nil, nil }}},
		Signals: map[string]string{"Closed": ""},
	})
	if err != nil {
		return responseOther, nil
	}
	s.unexport = unexport
	p.mu.Lock()
	p.sessions[c.session] = s
	p.mu.Unlock()
	if !s.forward {
		return responseOK, nil
	}
	code, results := p.request(ctx, conn, c, true, func(ctx context.Context) (uint32, map[string]dbus.Variant) {
		return relay(ctx, conn, "CreateSession", c)
	})
	if code != responseOK {
		p.forget(s)
	}
	return code, results
}

func (p *Portal) selectSources(ctx context.Context, conn *dbus.Conn, c call) (uint32, map[string]dbus.Variant) {
	s := p.session(c.session)
	if s == nil {
		return responseOther, nil
	}
	if s.forward {
		return p.request(ctx, conn, c, true, func(ctx context.Context) (uint32, map[string]dbus.Variant) {
			return relay(ctx, conn, "SelectSources", c)
		})
	}
	types, _ := c.options["types"].Value.(uint32)
	if types == 0 {
		types = sourceMonitor
	}
	cursor, _ := c.options["cursor_mode"].Value.(uint32)
	persist, _ := c.options["persist_mode"].Value.(uint32)
	return p.request(ctx, conn, c, false, func(ctx context.Context) (uint32, map[string]dbus.Variant) {
		outputs, windows, err := p.o.Sources(ctx)
		if err != nil {
			p.o.Log.Warn("screen share: listing what can be shared", "err", err)
			return responseOther, nil
		}
		if types&sourceMonitor == 0 {
			outputs = []Output{}
		}
		if types&sourceWindow == 0 {
			windows = []Window{}
		}
		r := Request{Backend: BackendNiri, AppID: c.appID, Outputs: outputs, Windows: windows}
		var choice *Choice
		if p.o.Settings().Remember {
			choice = restored(c.options["restore_data"], r)
		}
		if choice == nil {
			choice, err = p.o.Ask(ctx, r)
			switch {
			case err != nil:
				p.o.Log.Warn("screen share: no picker", "err", err)
				return responseOther, nil
			case choice == nil:
				return responseCancelled, nil
			case !choice.valid(r): // a region too: r offers none
				return responseOther, nil
			}
		}
		p.mu.Lock()
		s.types, s.cursor, s.persist, s.choice = types, cursor, persist, choice
		s.picked = restoreData(*choice, r)
		p.mu.Unlock()
		return responseOK, nil
	})
}

// restoreData is what a choice is remembered by: an output by name, a
// window by its app and title (its id won't outlive it).
func restoreData(c Choice, r Request) map[string]dbus.Variant {
	if c.Kind == KindScreen {
		return map[string]dbus.Variant{"output": dbus.MakeVariant(c.Output)}
	}
	for _, w := range r.Windows {
		if w.Token == c.Window {
			return map[string]dbus.Variant{"appId": dbus.MakeVariant(w.AppID), "title": dbus.MakeVariant(w.Title)}
		}
	}
	return nil
}

// restored is the choice restore data names, when r still offers it: the
// window with that app and title, else that app's only window.
func restored(v dbus.Variant, r Request) *Choice {
	data, ok := v.Value.([]any)
	if !ok || len(data) != 3 {
		return nil
	}
	vendor, _ := data[0].(string)
	version, _ := data[1].(uint32)
	inner, _ := data[2].(dbus.Variant)
	fields, _ := inner.Value.(map[string]dbus.Variant)
	if vendor != restoreVendor || version != restoreVersion || fields == nil {
		return nil
	}
	str := func(k string) string { s, _ := fields[k].Value.(string); return s }
	if out := str("output"); out != "" {
		c := &Choice{Kind: KindScreen, Output: out}
		if c.valid(r) {
			return c
		}
		return nil
	}
	app, title := str("appId"), str("title")
	if app == "" {
		return nil
	}
	var same []Window
	for _, w := range r.Windows {
		if w.AppID == app {
			if w.Title == title {
				return &Choice{Kind: KindWindow, Window: w.Token}
			}
			same = append(same, w)
		}
	}
	if len(same) == 1 {
		return &Choice{Kind: KindWindow, Window: same[0].Token}
	}
	return nil
}

func (p *Portal) start(ctx context.Context, conn *dbus.Conn, c call) (uint32, map[string]dbus.Variant) {
	s := p.session(c.session)
	if s == nil {
		return responseOther, nil
	}
	if s.forward {
		return p.request(ctx, conn, c, true, func(ctx context.Context) (uint32, map[string]dbus.Variant) {
			return relay(ctx, conn, "Start", c)
		})
	}
	p.mu.Lock()
	choice, cursor, persist, picked := s.choice, s.cursor, s.persist, s.picked
	p.mu.Unlock()
	if choice == nil {
		return responseOther, nil
	}
	return p.request(ctx, conn, c, false, func(ctx context.Context) (uint32, map[string]dbus.Variant) {
		node, size, err := p.cast(ctx, conn, s, *choice, mutterCursor(cursor))
		if err != nil {
			p.o.Log.Warn("screen share: niri didn't cast", "err", err)
			return responseOther, nil
		}
		source := sourceMonitor
		if choice.Kind == KindWindow {
			source = sourceWindow
		}
		props := map[string]dbus.Variant{"source_type": dbus.MakeVariant(source)}
		if size != nil {
			props["size"] = dbus.Variant{Sig: "(ii)", Value: []any{size[0], size[1]}}
		}
		results := map[string]dbus.Variant{
			"streams": dbus.Variant{Sig: "a(ua{sv})", Value: []any{[]any{node, props}}},
		}
		if persist != 0 && picked != nil && p.o.Settings().Remember {
			results["persist_mode"] = dbus.MakeVariant(persist)
			results["restore_data"] = dbus.Variant{Sig: "(suv)", Value: []any{restoreVendor, restoreVersion, dbus.MakeVariant(picked)}}
		}
		return responseOK, results
	})
}

// mutterCursor is a portal cursor mode as Mutter's API takes it.
func mutterCursor(mode uint32) uint32 {
	switch mode {
	case cursorEmbedded:
		return 1
	case cursorMetadata:
		return 2
	}
	return 0
}

// cast has niri cast the choice: the PipeWire node, and a monitor's size.
func (p *Portal) cast(ctx context.Context, conn *dbus.Conn, s *castSession, c Choice, cursor uint32) (uint32, []int32, error) {
	m, err := conn.Call(ctx, mutterBusName, mutterPath, ifaceMutter, "CreateSession", "a{sv}", map[string]dbus.Variant{})
	if err != nil {
		return 0, nil, err
	}
	var session dbus.ObjectPath
	err = m.Store(&session)
	m.Close()
	if err != nil {
		return 0, nil, err
	}
	// A session closed meanwhile never learns of niri's: stop it here
	p.mu.Lock()
	open := p.sessions[s.handle] == s
	if open {
		s.mutter = session
	}
	p.mu.Unlock()
	if !open {
		stop, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		conn.Call(stop, mutterBusName, session, ifaceMSession, "Stop", "")
		cancel()
		return 0, nil, errors.New("the session closed")
	}
	props := map[string]dbus.Variant{"cursor-mode": dbus.MakeVariant(cursor), "is-recording": dbus.MakeVariant(false)}
	if c.Kind == KindWindow {
		var id uint64
		for i := range len(c.Window) {
			ch := c.Window[i]
			if ch < '0' || ch > '9' {
				return 0, nil, errors.New("not a niri window id: " + c.Window)
			}
			id = id*10 + uint64(ch-'0')
		}
		props["window-id"] = dbus.MakeVariant(id)
		m, err = conn.Call(ctx, mutterBusName, session, ifaceMSession, "RecordWindow", "a{sv}", props)
	} else {
		m, err = conn.Call(ctx, mutterBusName, session, ifaceMSession, "RecordMonitor", "sa{sv}", c.Output, props)
	}
	if err != nil {
		return 0, nil, err
	}
	var stream dbus.ObjectPath
	err = m.Store(&stream)
	m.Close()
	if err != nil {
		return 0, nil, err
	}
	added, err := conn.Subscribe(ctx, dbus.Match{Path: stream, Interface: ifaceMStream, Member: "PipeWireStreamAdded"})
	if err != nil {
		return 0, nil, err
	}
	defer added.Close()
	var size []int32
	if c.Kind == KindScreen {
		if v, err := conn.GetProperty(ctx, mutterBusName, stream, ifaceMStream, "Parameters"); err == nil {
			if params, ok := v.Value.(map[string]dbus.Variant); ok {
				if wh, ok := params["size"].Value.([]any); ok && len(wh) == 2 {
					w, _ := wh[0].(int32)
					h, _ := wh[1].(int32)
					size = []int32{w, h}
				}
			}
		}
	}
	if m, err = conn.Call(ctx, mutterBusName, session, ifaceMSession, "Start", ""); err != nil {
		return 0, nil, err
	}
	m.Close()
	wait, cancel := context.WithTimeout(ctx, streamTimeout)
	defer cancel()
	for {
		select {
		case <-wait.Done():
			return 0, nil, errors.New("no stream from niri")
		case sig, ok := <-added.C:
			if !ok {
				return 0, nil, errors.New("the bus connection ended")
			}
			var node uint32
			if sig.Store(&node) == nil {
				return node, size, nil
			}
		}
	}
}

// close ends a session: niri's cast stops, a relayed one is closed at
// xdg-desktop-portal-gnome, and with emit, the frontend is told.
func (p *Portal) close(conn *dbus.Conn, s *castSession, emit bool) {
	if !p.forget(s) {
		return
	}
	// Forgotten, it gets no niri session after this (cast)
	p.mu.Lock()
	mutter := s.mutter
	p.mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	switch {
	case s.forward:
		conn.Call(ctx, gnomeBusName, s.handle, ifaceSession, "Close", "")
	case mutter != "":
		conn.Call(ctx, mutterBusName, mutter, ifaceMSession, "Stop", "")
	}
	if emit {
		conn.Emit(s.handle, ifaceSession, "Closed", "")
	}
}

// forget drops a session (false when it was already). A pick running for
// it ends when the frontend closes its request.
func (p *Portal) forget(s *castSession) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.sessions[s.handle] != s {
		return false
	}
	delete(p.sessions, s.handle)
	if s.unexport != nil {
		s.unexport()
	}
	return true
}

// ended closes the sessions niri or xdg-desktop-portal-gnome ended.
func (p *Portal) ended(conn *dbus.Conn, match func(*castSession) bool) {
	p.mu.Lock()
	var ended []*castSession
	for _, s := range p.sessions {
		if match(s) {
			ended = append(ended, s)
		}
	}
	p.mu.Unlock()
	for _, s := range ended {
		p.close(conn, s, true)
	}
}

// closeAll ends every session as the portal stops.
func (p *Portal) closeAll(conn *dbus.Conn) {
	p.ended(conn, func(*castSession) bool { return true })
}
