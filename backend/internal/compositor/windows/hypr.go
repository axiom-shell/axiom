package windows

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
)

// hyprSource reads Hyprland: socket2's events and j/clients. Frequent
// events (a title, the focus, a close) are applied from their payload;
// structural ones refetch the list.
type hyprSource struct {
	h        *ipc.Hypr
	monitors map[int]string // monitor id → name
	focus    string         // the focused window's id: from the events, never j/clients
}

func (s *hyprSource) connect(ctx context.Context, started func(), event func([]byte)) error {
	return s.h.Events(ctx, started, func(line string) { event([]byte(line)) })
}

func (s *hyprSource) request(ctx context.Context, name string) ([]byte, error) {
	reply, err := s.h.Request(ctx, name)
	return []byte(reply), err
}

func (s *hyprSource) reset()      { s.monitors, s.focus = nil, "" }
func (s *hyprSource) ready() bool { return true }

// snapshot: the monitors come before the clients, which name them by id
func (s *hyprSource) snapshot() []string {
	return []string{"j/activewindow", "j/monitors", "j/clients"}
}

func (s *hyprSource) apply(t, pend *table, line []byte) []string {
	name, data, _ := strings.Cut(string(line), ">>")
	switch name {
	case "windowtitlev2":
		// The title may hold commas: the address is up to the first
		addr, title, _ := strings.Cut(data, ",")
		for _, x := range []*table{t, pend} {
			x.update(hyprID(addr), func(w *Window) { w.Title = title })
		}
	case "activewindowv2":
		s.focus = hyprID(data)
		t.focus(s.focus)
		pend.focus(s.focus)
	case "closewindow":
		t.remove(hyprID(data))
		pend.remove(hyprID(data))
	case "openwindow":
		// ADDR,WORKSPACE,CLASS,TITLE
		if p := strings.SplitN(data, ",", 4); len(p) == 4 {
			id := hyprID(p[0])
			pend.add(Window{ID: id, AppID: p[2], Title: p[3], Workspace: p[1], Focused: id == s.focus})
		}
		return []string{"j/clients"}
	case "monitoraddedv2", "monitorremovedv2":
		return []string{"j/monitors", "j/clients"}
	case "movewindowv2", "changefloatingmode", "fullscreen", "moveworkspacev2", "renameworkspace", "configreloaded":
		return []string{"j/clients"}
	}
	return nil
}

func (s *hyprSource) load(ctx context.Context, f fetch, name string, reply []byte, t *table) error {
	switch name {
	case "j/activewindow":
		var active struct{ Address string }
		if err := json.Unmarshal(reply, &active); err != nil {
			return err
		}
		s.focus = hyprID(active.Address)
	case "j/monitors":
		return s.loadMonitors(reply)
	case "j/clients":
		return s.loadClients(ctx, f, reply, t)
	}
	return nil
}

// hyprID is an event's address as j/clients writes it: socket2 leaves the
// 0x off. "" and "," (no window) stay "".
func hyprID(addr string) string {
	if addr == "" || addr == "," {
		return ""
	}
	if strings.HasPrefix(addr, "0x") {
		return addr
	}
	return "0x" + addr
}

func (s *hyprSource) loadMonitors(reply []byte) error {
	var list []struct {
		ID   int
		Name string
	}
	if err := json.Unmarshal(reply, &list); err != nil {
		return err
	}
	s.monitors = make(map[int]string, len(list))
	for _, m := range list {
		s.monitors[m.ID] = m.Name
	}
	return nil
}

// loadClients replaces the table with j/clients' mapped windows, fetching
// the monitors again once when a client is on one that isn't known. The
// focus stays what the events said.
func (s *hyprSource) loadClients(ctx context.Context, f fetch, reply []byte, t *table) error {
	var clients []struct {
		Address    string
		Mapped     bool
		Floating   bool
		Monitor    int
		Class      string
		Title      string
		PID        int
		XWayland   bool
		Fullscreen int
		Workspace  struct{ Name string }
	}
	if err := json.Unmarshal(reply, &clients); err != nil {
		return err
	}
	for _, c := range clients {
		// -1: on no monitor yet, which no monitor list will ever name
		if _, ok := s.monitors[c.Monitor]; !ok && c.Monitor >= 0 && c.Mapped {
			if err := fetchLoad(ctx, f, s, "j/monitors", t); err != nil {
				return err
			}
			break
		}
	}
	var list []Window
	for _, c := range clients {
		if !c.Mapped {
			continue
		}
		w := Window{
			ID: c.Address, AppID: c.Class, Title: c.Title, PID: c.PID, XWayland: c.XWayland,
			Workspace: c.Workspace.Name, Output: s.monitors[c.Monitor],
			Floating: c.Floating, Fullscreen: c.Fullscreen&2 != 0, Focused: c.Address == s.focus,
		}
		if c.XWayland {
			w.Class = c.Class
		}
		list = append(list, w)
	}
	t.list = list
	return nil
}
