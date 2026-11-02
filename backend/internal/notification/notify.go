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
	// An icon name or a picture's path ("": none)
	Icon string `json:"icon,omitempty"`
	// The desktop-entry hint: which app clicking it leads to
	DesktopEntry string `json:"desktopEntry,omitempty"`
	// "low" | "normal" | "critical" ("": normal)
	Urgency string `json:"urgency,omitempty"`
	// Its buttons
	Actions []Action `json:"actions,omitempty"`
}

// Action is a button: the id Send answers when it's picked, and its text.
type Action struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// Send shows n. Without actions it returns once the server took it; with
// them it waits until one is picked (its id) or the notification closes
// (""), or ctx ends.
func Send(ctx context.Context, conn *dbus.Conn, n Notification) (string, error) {
	setup, cancel := context.WithTimeout(ctx, sendTimeout)
	defer cancel()
	var sub *dbus.Subscription
	if len(n.Actions) > 0 {
		// Subscribed before the call, so a quick pick isn't missed
		var err error
		if sub, err = conn.Subscribe(setup, dbus.Match{Sender: busName, Path: path, Interface: iface}); err != nil {
			return "", axerr.Wrap(axerr.Unavailable, err, "listening for the notification's buttons")
		}
		defer sub.Close()
	}
	reply, err := conn.Call(setup, busName, path, iface, "Notify", "susssasa{sv}i",
		n.AppName, uint32(0), n.Icon, n.Summary, n.Body, actionList(n.Actions), hints(n), int32(-1))
	if err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "no notification server took it")
	}
	if sub == nil {
		return "", nil
	}
	var id uint32
	if err := reply.Store(&id); err != nil {
		return "", axerr.Wrap(axerr.Internal, err, "reading the notification's id")
	}
	for {
		select {
		case <-ctx.Done():
			return "", nil
		case m, ok := <-sub.C:
			if !ok {
				return "", nil
			}
			if len(m.Body) < 2 || m.Body[0] != id {
				continue
			}
			switch m.Member {
			case "ActionInvoked":
				picked, _ := m.Body[1].(string)
				return picked, nil
			case "NotificationClosed":
				return "", nil
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
	if n.DesktopEntry != "" {
		h["desktop-entry"] = dbus.MakeVariant(n.DesktopEntry)
	}
	switch n.Urgency {
	case "low":
		h["urgency"] = dbus.MakeVariant(uint8(0))
	case "critical":
		h["urgency"] = dbus.MakeVariant(uint8(2))
	}
	return h
}
