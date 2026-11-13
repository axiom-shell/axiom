package windows

import (
	"context"
	"encoding/json"
	"strconv"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
)

// swaySource reads sway: window and workspace events and get_tree. A
// window's other fields change from the event's container; where it
// lives (workspace, output) only the tree knows.
type swaySource struct {
	s *ipc.Sway
}

func (s *swaySource) connect(ctx context.Context, started func(), event func([]byte)) error {
	return s.s.Events(ctx, []string{"window", "workspace"}, started, func(kind uint32, body []byte) {
		var name string
		switch kind {
		case ipc.SwayEventWindow:
			name = "window"
		case ipc.SwayEventWorkspace:
			name = "workspace"
		default:
			return
		}
		// {"type": …, "body": …}: the shape the fixtures hold
		line, err := json.Marshal(struct {
			Type string          `json:"type"`
			Body json.RawMessage `json:"body"`
		}{name, body})
		if err == nil {
			event(line)
		}
	})
}

// swayNode is a get_tree node, or a window event's container
type swayNode struct {
	ID               int64                  `json:"id"`
	Name             string                 `json:"name"`
	Type             string                 `json:"type"`
	AppID            string                 `json:"app_id"`
	PID              int                    `json:"pid"`
	Shell            string                 `json:"shell"`
	Focused          bool                   `json:"focused"`
	FullscreenMode   int                    `json:"fullscreen_mode"`
	WindowProperties struct{ Class string } `json:"window_properties"`
	Nodes            []swayNode             `json:"nodes"`
	FloatingNodes    []swayNode             `json:"floating_nodes"`
}

// window is the node as a Window with no workspace or output
func (n swayNode) window() Window {
	w := Window{
		ID: strconv.FormatInt(n.ID, 10), AppID: n.AppID, Title: n.Name, PID: n.PID,
		XWayland: n.Shell == "xwayland", Floating: n.Type == "floating_con",
		Fullscreen: n.FullscreenMode > 0, Focused: n.Focused,
	}
	if n.WindowProperties.Class != "" {
		w.Class = n.WindowProperties.Class
		if w.AppID == "" {
			w.AppID = w.Class
		}
	}
	return w
}

func (s *swaySource) start(ctx context.Context, f fetch, t *table) (bool, error) {
	t.list = nil
	return true, s.refetch(ctx, f, t)
}

// refetch replaces the table with get_tree's windows
func (s *swaySource) refetch(ctx context.Context, f fetch, t *table) error {
	reply, err := f(ctx, "get_tree")
	if err != nil {
		return err
	}
	var root swayNode
	if err := json.Unmarshal(reply, &root); err != nil {
		return err
	}
	t.list = nil
	for _, output := range root.Nodes {
		for _, ws := range output.Nodes {
			if ws.Type != "workspace" {
				continue
			}
			name, out := ws.Name, output.Name
			// The scratchpad is a workspace of its own, on no output
			if output.Name == "__i3" && ws.Name == "__i3_scratch" {
				name, out = "", ""
			}
			t.list = walk(t.list, ws, name, out)
		}
	}
	return nil
}

// walk adds the windows under n (leaves with a pid) to list
func walk(list []Window, n swayNode, ws, output string) []Window {
	for _, kids := range [][]swayNode{n.Nodes, n.FloatingNodes} {
		for _, c := range kids {
			if len(c.Nodes) == 0 && len(c.FloatingNodes) == 0 {
				if c.PID > 0 {
					w := c.window()
					w.Workspace, w.Output = ws, output
					list = append(list, w)
				}
				continue
			}
			list = walk(list, c, ws, output)
		}
	}
	return list
}

func (s *swaySource) batch(ctx context.Context, f fetch, t *table, events [][]byte) (bool, error) {
	refetch := false
	// Windows opened in this batch as their container describes them, for a
	// tree that doesn't have one yet
	opened := map[string]Window{}
	var order []string
	for _, e := range events {
		var event struct {
			Type string `json:"type"`
			Body struct {
				Change    string   `json:"change"`
				Container swayNode `json:"container"`
			} `json:"body"`
		}
		if json.Unmarshal(e, &event) != nil {
			continue
		}
		b := event.Body
		if event.Type == "workspace" {
			if b.Change == "move" || b.Change == "rename" || b.Change == "reload" {
				refetch = true
			}
			continue
		}
		w := b.Container.window()
		switch b.Change {
		case "close":
			t.remove(w.ID)
			delete(opened, w.ID)
		case "new", "move":
			if b.Change == "new" {
				if _, ok := opened[w.ID]; !ok {
					order = append(order, w.ID)
				}
				opened[w.ID] = w
			}
			refetch = true
		default:
			if b.Change == "focus" {
				t.focus(w.ID)
			}
			t.update(w.ID, func(old *Window) {
				w.Workspace, w.Output = old.Workspace, old.Output
				if b.Change != "focus" {
					w.Focused = old.Focused
				}
				*old = w
			})
			if o, ok := opened[w.ID]; ok {
				w.Workspace, w.Output = o.Workspace, o.Output
				opened[w.ID] = w
			}
		}
	}
	if refetch {
		if err := s.refetch(ctx, f, t); err != nil {
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
