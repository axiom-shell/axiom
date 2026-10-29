package steps

import "github.com/axiom-shell/axiom/backend/internal/jsonx"

// v82: Compositor.niri.hotCorner goes, since managed mode always turns
// niri's own corner off and hot corners are axiom's (HotCorners). On, in
// managed mode (the only one that wrote it), it becomes a top-left corner
// on every monitor opening the workspace overview, which with
// WorkspaceOverlay.compositorOverview is niri's as before.
func v82(cfg *jsonx.Object) []string {
	niri := object(cfg, "Compositor", "niri")
	if niri == nil || !niri.Has("hotCorner") {
		return nil
	}
	on := niri.Value("hotCorner") == true
	niri.Delete("hotCorner")
	if !on || object(cfg, "Compositor").Value("mode") != "managed" {
		return []string{"Compositor.niri.hotCorner removed: hot corners are axiom's own (HotCorners)"}
	}
	items, taken := sectionItems(cfg, "HotCorners")
	if items == nil {
		return []string{"Compositor.niri.hotCorner removed: HotCorners or its items are of another shape, so no corner was added"}
	}
	items.Append(jsonx.Obj(
		"id", freeID("niri-corner", taken),
		"corner", "topLeft",
		"action", "workspaceOverview",
		"argument", "",
		"screen", jsonx.Obj("mode", "all", "names", jsonx.Arr()),
		"delay", 0.0,
	))
	return []string{"Compositor.niri.hotCorner became a top-left hot corner opening the workspace overview (HotCorners.items)"}
}
