// Package notification sends one of axiom's own desktop notifications
// (`notify.send`, the shell's NotificationManager.sendNotification) over
// the session bus to whatever serves org.freedesktop.Notifications (the
// shell's own server, so it comes back like any other), the way
// notify-send did; with buttons it waits for the one picked.
package notification

import (
	"context"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
)

const (
	busName = "org.freedesktop.Notifications"
	path    = dbus.ObjectPath("/org/freedesktop/Notifications")
	iface   = "org.freedesktop.Notifications"
	// How long the bus and the server get to take it; waiting for a
	// button has no limit
	sendTimeout = 5 * time.Second
)

// Notification is what to show.
type Notification struct {
	AppName string `json:"appName"`
	Summary string `json:"summary"`
	Body    string `json:"body"`
	// An icon name or a picture's path ("": none), sent as the
	// image-path hint as notify-send -i did (the app icon stays empty)
	Icon string `json:"icon,omitempty"`
	// The desktop-entry hint: which app clicking it leads to
	DesktopEntry string `json:"desktopEntry,omitempty"`
	// "low" | "normal" | "critical" ("": normal)
	Urgency string `json:"urgency,omitempty"`
	// Its buttons
	Actions []Action `json:"actions,omitempty"`
	// The x-axiom-key hint: a notification of the same key replaces this
	// one in the shell's history (one entry per key, never a pile)
	Key string `json:"key,omitempty"`
	// The transient hint: shown, never filed in a history (an answer to
	// what was just done)
	Transient bool `json:"transient,omitempty"`
}

// Action is a button: the id Send answers when it's picked, and its text.
type Action struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// Sent is a notification shown: its id, and with buttons what Wait
// listens to.
type Sent struct {
	ID  uint32
	sub *dbus.Subscription
}

// Send shows n and returns once the server took it.
func Send(ctx context.Context, conn *dbus.Conn, n Notification) (Sent, error) {
	setup, cancel := context.WithTimeout(ctx, sendTimeout)
	defer cancel()
	var sent Sent
	if len(n.Actions) > 0 {
		// Subscribed before the call, so a quick pick isn't missed
		var err error
		if sent.sub, err = conn.Subscribe(setup, dbus.Match{Sender: busName, Path: path, Interface: iface}); err != nil {
			return Sent{}, axerr.Wrap(axerr.Unavailable, err, "listening for the notification's buttons")
		}
	}
	fail := func(err error) (Sent, error) {
		if sent.sub != nil {
			sent.sub.Close()
		}
		return Sent{}, err
	}
	reply, err := conn.Call(setup, busName, path, iface, "Notify", "susssasa{sv}i",
		n.AppName, uint32(0), "", n.Summary, n.Body, actionList(n.Actions), hints(n), int32(-1))
	if err != nil {
		return fail(axerr.Wrap(axerr.Unavailable, err, "no notification server took it"))
	}
	if err := reply.Store(&sent.ID); err != nil {
		return fail(axerr.Wrap(axerr.Internal, err, "reading the notification's id"))
	}
	return sent, nil
}

// Wait answers the id of the button picked, or "" once the notification
// closes, the bus does, ctx ends or gone closes (at once without buttons).
func (s Sent) Wait(ctx context.Context, gone <-chan struct{}) string {
	if s.sub == nil {
		return ""
	}
	defer s.sub.Close()
	for {
		select {
		case <-ctx.Done():
			return ""
		case <-gone:
			return ""
		case m, ok := <-s.sub.C:
			if !ok {
				return ""
			}
			if len(m.Body) < 2 || m.Body[0] != s.ID {
				continue
			}
			switch m.Member {
			case "ActionInvoked":
				picked, _ := m.Body[1].(string)
				return picked
			case "NotificationClosed":
				return ""
			}
		}
	}
}

// actionList is Notify's actions: each id followed by its label.
func actionList(actions []Action) []string {
	out := make([]string, 0, 2*len(actions))
	for _, a := range actions {
		out = append(out, a.ID, a.Label)
	}
	return out
}

// hints are Notify's hints for n.
func hints(n Notification) map[string]dbus.Variant {
	h := map[string]dbus.Variant{}
	if n.Icon != "" {
		h["image-path"] = dbus.MakeVariant(n.Icon)
	}
	if n.DesktopEntry != "" {
		h["desktop-entry"] = dbus.MakeVariant(n.DesktopEntry)
	}
	if n.Key != "" {
		h["x-axiom-key"] = dbus.MakeVariant(n.Key)
	}
	if n.Transient {
		h["transient"] = dbus.MakeVariant(true)
	}
	switch n.Urgency {
	case "low":
		h["urgency"] = dbus.MakeVariant(uint8(0))
	case "critical":
		h["urgency"] = dbus.MakeVariant(uint8(2))
	}
	return h
}
