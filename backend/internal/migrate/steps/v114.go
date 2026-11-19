package steps

import "github.com/axiom-shell/axiom/backend/internal/jsonx"

// v114 moves the overlay's Module size (`Overlay.moduleScale`) onto each of
// its pages, as that page's own sizing: a Custom page's Card size (its cards
// and content grew together by it, which the sizing's link does by default),
// a tool page's Content size (the whole page zoomed by it). A value of 100
// was the default and is just removed, as is one without pages to put it on:
// a sparse snapshot or export without Overlay.items loses the value (back
// to 100%), accepted as no one set it. A `sizing` already on a page wins; a
// `moduleScale` that isn't a number is left alone.
func v114(cfg *jsonx.Object) []string {
	overlay := object(cfg, "Overlay")
	if overlay == nil {
		return nil
	}
	scale, isNumber := overlay.Value("moduleScale").(float64)
	if !isNumber {
		return nil
	}
	overlay.Delete("moduleScale")
	items, _ := overlay.Value("items").(*jsonx.Array)
	if scale != 100 && items != nil {
		for _, entry := range items.Items {
			page, _ := entry.(*jsonx.Object)
			if page == nil || page.Has("sizing") {
				continue
			}
			key := "contentSize"
			if page.Value("type") == "Custom" {
				key = "cardSize"
			}
			page.Set("sizing", jsonx.Obj(key, scale))
		}
	}
	return []string{"Overlay.moduleScale moved onto each page's sizing"}
}
