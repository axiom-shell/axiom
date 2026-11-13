package windows

import (
	"context"
	"encoding/json"
	"math"
	"strconv"

	"github.com/axiom-shell/axiom/backend/internal/compositor/ipc"
)

// niriSource reads niri's event stream, which is its whole state: windows
// and workspaces are kept as niri sends them and turned into Windows after
// each batch. Output sizes (for fullscreen) are the one thing it asks for.
type niriSource struct {
	n *ipc.Niri

	windows   []ipc.NiriWindow
	workspace map[uint64]niriWorkspace
	sizes     map[string][2]float64 // output name → logical width and height
	seen      bool                  // WindowsChanged was applied
	fresh     bool                  // sizes were read at start, no batch since
}

type niriWorkspace struct {
	idx          int
	name, output string
}

func (s *niriSource) connect(ctx context.Context, started func(), event func([]byte)) error {
	return s.n.Events(ctx, started, event)
}

func (s *niriSource) start(ctx context.Context, f fetch, t *table) (bool, error) {
	s.windows, s.workspace, s.seen, s.fresh = nil, map[uint64]niriWorkspace{}, false, true
	t.list = nil
	return false, s.fetchSizes(ctx, f)
}

func (s *niriSource) fetchSizes(ctx context.Context, f fetch) error {
	reply, err := f(ctx, "Outputs")
	if err != nil {
		return err
	}
	var outputs map[string]struct {
		Logical *struct{ Width, Height float64 }
	}
	if err := json.Unmarshal(reply, &outputs); err != nil {
		return err
	}
	s.sizes = map[string][2]float64{}
	for name, o := range outputs {
		if o.Logical != nil {
			s.sizes[name] = [2]float64{o.Logical.Width, o.Logical.Height}
		}
	}
	return nil
}

func (s *niriSource) batch(ctx context.Context, f fetch, t *table, events [][]byte) (bool, error) {
	workspaces := false
	for _, line := range events {
		var event map[string]json.RawMessage
		if json.Unmarshal(line, &event) != nil {
			continue
		}
		for name, body := range event {
			switch name {
			case "WorkspacesChanged":
				var e struct {
					Workspaces []struct {
						ID     uint64
						Idx    int
						Name   *string
						Output string
					}
				}
				if json.Unmarshal(body, &e) != nil {
					continue
				}
				s.workspace = map[uint64]niriWorkspace{}
				for _, w := range e.Workspaces {
					ws := niriWorkspace{idx: w.Idx, output: w.Output}
					if w.Name != nil {
						ws.name = *w.Name
					}
					s.workspace[w.ID] = ws
				}
				workspaces = true
			case "WindowsChanged":
				var e struct{ Windows []ipc.NiriWindow }
				if json.Unmarshal(body, &e) != nil {
					continue
				}
				s.windows, s.seen = e.Windows, true
			case "WindowOpenedOrChanged":
				var e struct{ Window ipc.NiriWindow }
				if json.Unmarshal(body, &e) != nil {
					continue
				}
				s.opened(e.Window)
			case "WindowClosed":
				var e struct{ ID uint64 }
				if json.Unmarshal(body, &e) == nil {
					s.closed(e.ID)
				}
			case "WindowFocusChanged":
				var e struct{ ID *uint64 }
				if json.Unmarshal(body, &e) == nil {
					s.focus(e.ID)
				}
			case "WindowLayoutsChanged":
				var e struct {
					Changes [][2]json.RawMessage
				}
				if json.Unmarshal(body, &e) != nil {
					continue
				}
				for _, c := range e.Changes {
					var id uint64
					var layout ipc.NiriLayout
					if json.Unmarshal(c[0], &id) == nil && json.Unmarshal(c[1], &layout) == nil {
						for i := range s.windows {
							if s.windows[i].ID == id {
								s.windows[i].Layout = &layout
							}
						}
					}
				}
			}
		}
	}
	if workspaces && !s.fresh {
		if err := s.fetchSizes(ctx, f); err != nil {
			return s.seen, err
		}
	}
	s.fresh = false
	t.list = t.list[:0]
	if !s.seen {
		return false, nil
	}
	for _, w := range s.windows {
		t.list = append(t.list, s.window(w))
	}
	return true, nil
}

// opened adds or replaces a window; one that opens focused unfocuses the
// others, as niri sends no WindowFocusChanged for it
func (s *niriSource) opened(w ipc.NiriWindow) {
	if w.Focused {
		s.focus(nil)
	}
	for i := range s.windows {
		if s.windows[i].ID == w.ID {
			s.windows[i] = w
			return
		}
	}
	s.windows = append(s.windows, w)
}

func (s *niriSource) closed(id uint64) {
	for i := range s.windows {
		if s.windows[i].ID == id {
			s.windows = append(s.windows[:i], s.windows[i+1:]...)
			return
		}
	}
}

// focus focuses window id (nil: none)
func (s *niriSource) focus(id *uint64) {
	for i := range s.windows {
		s.windows[i].Focused = id != nil && s.windows[i].ID == *id
	}
}

func (s *niriSource) window(w ipc.NiriWindow) Window {
	out := Window{
		ID: strconv.FormatUint(w.ID, 10), AppID: w.AppID, Title: w.Title, PID: w.PID,
		Floating: w.Floating, Focused: w.Focused,
	}
	if w.WorkspaceID == nil {
		return out
	}
	ws := s.workspace[*w.WorkspaceID]
	out.Workspace, out.Output = ws.name, ws.output
	if ws.name == "" && ws.idx > 0 {
		out.Workspace = strconv.Itoa(ws.idx)
	}
	// A tiled window as big as its output is fullscreen (niri 26.04 has no
	// field for it; NiriState.windows reads it the same way)
	if size, ok := s.sizes[ws.output]; ok && !w.Floating && w.Layout != nil && len(w.Layout.TileSize) == 2 {
		out.Fullscreen = math.Abs(w.Layout.TileSize[0]-size[0]) <= 1 && math.Abs(w.Layout.TileSize[1]-size[1]) <= 1
	}
	return out
}
