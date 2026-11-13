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

func (s *hyprSource) start(ctx context.Context, f fetch, t *table) (bool, error) {
	s.monitors, s.focus = nil, ""
	t.list = nil
	reply, err := f(ctx, "j/activewindow")
	if err != nil {
		return false, err
	}
	var active struct{ Address string }
	if err := json.Unmarshal(reply, &active); err != nil {
		return false, err
	}
	s.focus = hyprID(active.Address)
	if err := s.fetchMonitors(ctx, f); err != nil {
		return false, err
	}
	if err := s.fetchClients(ctx, f, t); err != nil {
		return false, err
	}
	return true, nil
}

func (s *hyprSource) batch(ctx context.Context, f fetch, t *table, events [][]byte) (bool, error) {
	refetch, monitors := false, false
	// Windows opened in this batch as their events describe them, for one
	// j/clients doesn't have yet
	opened := map[string]Window{}
	var order []string
	for _, e := range events {
		name, data, _ := strings.Cut(string(e), ">>")
		switch name {
		case "windowtitlev2":
			// The title may hold commas: the address is up to the first
			addr, title, _ := strings.Cut(data, ",")
			id := hyprID(addr)
			t.update(id, func(w *Window) { w.Title = title })
			if w, ok := opened[id]; ok {
				w.Title = title
				opened[id] = w
			}
		case "activewindowv2":
			s.focus = hyprID(data)
			t.focus(s.focus)
		case "closewindow":
			id := hyprID(data)
			t.remove(id)
			delete(opened, id)
		case "openwindow":
			// ADDR,WORKSPACE,CLASS,TITLE
			p := strings.SplitN(data, ",", 4)
			if len(p) == 4 {
				id := hyprID(p[0])
				if _, ok := opened[id]; !ok {
					order = append(order, id)
				}
				opened[id] = Window{ID: id, AppID: p[2], Title: p[3], Workspace: p[1], Focused: id == s.focus}
			}
			refetch = true
		case "monitoraddedv2", "monitorremovedv2":
			monitors, refetch = true, true
		case "movewindowv2", "changefloatingmode", "fullscreen", "moveworkspacev2", "renameworkspace", "configreloaded":
			refetch = true
		}
	}
	if monitors {
		if err := s.fetchMonitors(ctx, f); err != nil {
			return true, err
		}
	}
	if refetch {
		if err := s.fetchClients(ctx, f, t); err != nil {
			return true, err
		}
		for _, id := range order {
			if w, ok := opened[id]; ok && t.find(id) < 0 {
				t.list = append(t.list, w)
			}
		}
	}
	return true, nil
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

func (s *hyprSource) fetchMonitors(ctx context.Context, f fetch) error {
	reply, err := f(ctx, "j/monitors")
	if err != nil {
		return err
	}
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

// fetchClients replaces the table with j/clients' mapped windows, fetching
// the monitors again once when a client is on one that isn't known. The
// focus stays what the events said.
func (s *hyprSource) fetchClients(ctx context.Context, f fetch, t *table) error {
	reply, err := f(ctx, "j/clients")
	if err != nil {
		return err
	}
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
			if err := s.fetchMonitors(ctx, f); err != nil {
				return err
			}
			break
		}
	}
	t.list = nil
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
		t.list = append(t.list, w)
	}
	return nil
}
