package steps

import (
	"fmt"
	"math"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v93: the bar's settings were remade (the bar rewrite).
//
//   - `background` split into `surface` (bar, pills, none) and `floating`;
//     an unknown or missing one is a bar, as `solid` was the default. A bar
//     that never set `lockCenter` keeps it off (its default is now on).
//   - `floatGap` became `floatingGap`, Automatic (-1) now null.
//   - widgetSize, padding, spacing, widgetPadding and widgetSpacing became
//     thickness, edgePadding, widgetGap, innerPadding and innerGap; the
//     inner two now scale with thickness, so they're set to what keeps
//     today's pixels at the bar's thickness. pillPadding and pillMerge went
//     (pills use edgePadding; groups join when the widget gap apart).
//   - A font size in px became `textScale`, a percentage at a 26 px
//     thickness that scales with it: the shared one against
//     Appearance.font.size, and each bar's own where it then differs.
//   - The leftCenter and rightCenter sections went: they join left and
//     right with a Spacer between.
//   - A Separator of style `space` became a Spacer of its size.
//   - A widget's layout `size` is a `maxSize` on the widgets that shrink
//     (Window, Media), else dropped, as is `minSize` on the others.
func v93(cfg *jsonx.Object) []string {
	bars := object(cfg, "Bars")
	if bars == nil {
		return nil
	}
	base := 14.0
	if font := object(cfg, "Appearance", "font"); font != nil {
		if size, ok := font.Value("size").(float64); ok && size > 0 {
			base = size
		}
	}
	var changes []string
	// The shared font size, which each bar's own scale is set against
	sharedFont, sharedScale := math.NaN(), 100.0
	if style, _ := bars.Value("style").(*jsonx.Object); style != nil {
		if scale, ok := style.Value("textScale").(float64); ok {
			sharedScale = scale
		}
		if style.Has("fontSize") {
			font, isNumber := style.Value("fontSize").(float64)
			if isNumber {
				sharedFont = font
			}
			if isNumber && !style.Has("textScale") {
				sharedScale = clampRound(100*font/base, 50, 200)
				style = renameKey(style, "fontSize", "textScale")
				style.Set("textScale", sharedScale)
				bars.Set("style", style)
				changes = append(changes, fmt.Sprintf("Bars.style.fontSize %v px became textScale %v%%", font, sharedScale))
			} else {
				style.Delete("fontSize")
				changes = append(changes, "Bars.style.fontSize removed: bar text follows textScale")
			}
		}
	}
	items, _ := bars.Value("items").(*jsonx.Array)
	if items == nil {
		return changes
	}
	var reshaped, unknown, joined, spacers, layouts int
	for i, item := range items.Items {
		bar, _ := item.(*jsonx.Object)
		if bar == nil {
			continue
		}
		touched := false
		// Renamed keys keep their place among the bar's keys
		for _, r := range [][2]string{{"widgetSize", "thickness"}, {"padding", "edgePadding"}, {"spacing", "widgetGap"}, {"widgetPadding", "innerPadding"}, {"widgetSpacing", "innerGap"}, {"floatGap", "floatingGap"}} {
			if !bar.Has(r[0]) {
				continue
			}
			touched = true
			if bar.Has(r[1]) {
				bar.Delete(r[0])
				continue
			}
			bar = renameKey(bar, r[0], r[1])
			switch r[1] {
			case "innerPadding", "innerGap":
				if v, ok := bar.Value(r[1]).(float64); ok {
					limit := 40.0
					if r[1] == "innerGap" {
						limit = 20
					}
					bar.Set(r[1], clampRound(v*26/thickness(bar), 0, limit))
				}
			case "floatingGap":
				if v, ok := bar.Value(r[1]).(float64); !ok || v < 0 {
					bar.Set(r[1], nil)
				}
			}
		}
		for _, key := range []string{"pillPadding", "pillMerge"} {
			if bar.Has(key) {
				bar.Delete(key)
				touched = true
			}
		}
		// A bar from before the split (no surface yet)
		if !bar.Has("surface") {
			surface, floating := "bar", false
			switch bar.Value("background") {
			case "solid":
			case "pills":
				surface = "pills"
			case "transparent":
				surface = "none"
			case "floating":
				floating = true
			case "floatingPills":
				surface, floating = "pills", true
			default:
				if bar.Has("background") {
					unknown++
				}
			}
			bar = renameKey(bar, "background", "surface")
			bar.Set("surface", surface)
			if !bar.Has("floating") {
				bar.Set("floating", floating)
			}
			if !bar.Has("lockCenter") {
				bar.Set("lockCenter", false)
			}
			// Its text as large as it was, at its thickness
			style, _ := bar.Value("style").(*jsonx.Object)
			font := sharedFont
			if style != nil {
				if own, ok := style.Value("fontSize").(float64); ok {
					font = own
				}
			}
			if math.IsNaN(font) {
				font = base
			}
			if style != nil {
				style.Delete("fontSize")
			}
			// Left out (null) where it's the shared one's
			if want := clampRound(100*font*26/(base*thickness(bar)), 50, 200); want != sharedScale && (style == nil || !style.Has("textScale")) {
				// A bar with no style, or a null one (all inherited), gets one
				if style == nil && bar.Value("style") == nil {
					style = jsonx.NewObject()
					bar.Set("style", style)
				}
				if style != nil {
					style.Set("textScale", want)
				}
			}
			touched = true
		} else if bar.Has("background") {
			bar.Delete("background")
			touched = true
		}
		if widgets, _ := bar.Value("widgets").(*jsonx.Object); widgets != nil {
			taken := widgetIDs(widgets)
			for _, side := range [][3]string{{"leftCenter", "left", "after"}, {"rightCenter", "right", "before"}} {
				if !widgets.Has(side[0]) {
					continue
				}
				extra, _ := widgets.Value(side[0]).(*jsonx.Array)
				widgets.Delete(side[0])
				touched = true
				if extra == nil || extra.Len() == 0 {
					continue
				}
				own, _ := widgets.Value(side[1]).(*jsonx.Array)
				merged := jsonx.Arr()
				spacer := jsonx.Obj("id", freeID("spacer", taken), "type", "Spacer")
				if side[2] == "after" {
					if own != nil {
						merged.Items = append(merged.Items, own.Items...)
					}
					merged.Items = append(merged.Items, spacer)
					merged.Items = append(merged.Items, extra.Items...)
				} else {
					merged.Items = append(merged.Items, extra.Items...)
					merged.Items = append(merged.Items, spacer)
					if own != nil {
						merged.Items = append(merged.Items, own.Items...)
					}
				}
				widgets.Set(side[1], merged)
				joined++
			}
			for _, section := range widgets.Keys() {
				list, _ := widgets.Value(section).(*jsonx.Array)
				if list == nil {
					continue
				}
				for j, w := range list.Items {
					widget, _ := w.(*jsonx.Object)
					if widget == nil {
						continue
					}
					if replaced := spaceToSpacer(widget); replaced != nil {
						list.Items[j] = replaced
						widget = replaced
						spacers++
						touched = true
					}
					if trimLayout(widget) {
						layouts++
						touched = true
					}
				}
			}
		}
		if touched {
			items.Items[i] = bar
			reshaped++
		}
	}
	if reshaped > 0 {
		changes = append(changes, fmt.Sprintf("Bars.items: %d bar(s) took the new bar settings (surface and floating for background, thickness, edge padding, widget gap, inner padding and gap rescaled to keep their pixels, text scale for font size)", reshaped))
	}
	if unknown > 0 {
		changes = append(changes, fmt.Sprintf("Bars.items: %d bar(s) had a background axiom doesn't know: now one bar, not floating", unknown))
	}
	if joined > 0 {
		changes = append(changes, fmt.Sprintf("Bars.items: %d leftCenter/rightCenter section(s) joined left or right after a Spacer", joined))
	}
	if spacers > 0 {
		changes = append(changes, fmt.Sprintf("Bars.items: %d space Separator(s) became Spacers", spacers))
	}
	if layouts > 0 {
		changes = append(changes, fmt.Sprintf("Bars.items: %d widget layout(s) lost a size: a maxSize on Window and Media, else dropped, and minSize only on them", layouts))
	}
	return changes
}

// elasticTypes are the widget types that shrink when their bar is crowded
// (`x-elastic`), as of v93: frozen here, as a step's view of the schema
var elasticTypes = map[string]bool{"Window": true, "Media": true}

// thickness is a bar's thickness (26 when it has none)
func thickness(bar *jsonx.Object) float64 {
	if t, ok := bar.Value("thickness").(float64); ok && t > 0 {
		return t
	}
	return 26
}

func clampRound(v, lo, hi float64) float64 {
	return math.Min(hi, math.Max(lo, math.Round(v)))
}

// widgetIDs is every id of a bar's widgets, in any section
func widgetIDs(widgets *jsonx.Object) map[string]bool {
	taken := map[string]bool{}
	for _, section := range widgets.Keys() {
		list, _ := widgets.Value(section).(*jsonx.Array)
		if list == nil {
			continue
		}
		for _, w := range list.Items {
			if o, _ := w.(*jsonx.Object); o != nil {
				if id, _ := o.Value("id").(string); id != "" {
					taken[id] = true
				}
			}
		}
	}
	return taken
}

// spaceToSpacer is the Spacer a space Separator becomes (its id, visible
// and layout kept, its size its minimum gap), or nil for any other widget
func spaceToSpacer(widget *jsonx.Object) *jsonx.Object {
	props, _ := widget.Value("properties").(*jsonx.Object)
	if widget.Value("type") != "Separator" || props == nil || props.Value("style") != "space" {
		return nil
	}
	size := 12.0
	if v, ok := props.Value("size").(float64); ok {
		size = v
	}
	out := jsonx.NewObject()
	for _, k := range widget.Keys() {
		switch k {
		case "type":
			out.Set(k, "Spacer")
		case "properties":
			out.Set(k, jsonx.Obj("minGap", size))
		default:
			out.Set(k, widget.Value(k))
		}
	}
	return out
}

// trimLayout drops the layout sizes a widget no longer takes (its size a
// maxSize on an elastic one), and the layout when that empties it; it
// says whether it changed anything
func trimLayout(widget *jsonx.Object) bool {
	layout, _ := widget.Value("layout").(*jsonx.Object)
	if layout == nil {
		return false
	}
	elastic := elasticTypes[jsonx.ToString(widget.Value("type"))]
	changed := false
	if layout.Has("size") {
		if elastic && !layout.Has("maxSize") {
			widget.Set("layout", renameKey(layout, "size", "maxSize"))
			layout = widget.Value("layout").(*jsonx.Object)
		} else {
			layout.Delete("size")
		}
		changed = true
	}
	if !elastic && layout.Has("minSize") {
		layout.Delete("minSize")
		changed = true
	}
	if changed && layout.Len() == 0 {
		widget.Delete("layout")
	}
	return changed
}
