package steps

import (
	"fmt"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// v94: the keyboard's layouts and variants (Input.keyboard.layout "us,de",
// variant ",neo") became the input sources (Input.keyboard.sources), an xkb source
// per layout, which IME engines join. A layout left empty is dropped; with
// none at all the default fills the list. Sources already there win.
func v94(cfg *jsonx.Object) []string {
	keyboard := object(cfg, "Input", "keyboard")
	if keyboard == nil || (!keyboard.Has("layout") && !keyboard.Has("variant")) {
		return nil
	}
	layout, _ := keyboard.Value("layout").(string)
	variant, _ := keyboard.Value("variant").(string)
	keyboard.Delete("layout")
	keyboard.Delete("variant")
	if keyboard.Has("sources") {
		return []string{"Input.keyboard.layout and variant were dropped: Input.keyboard.sources holds the layouts"}
	}
	variants := strings.Split(variant, ",")
	sources := jsonx.Arr()
	ids := map[string]bool{}
	for i, l := range strings.Split(layout, ",") {
		l = strings.TrimSpace(l)
		if l == "" {
			continue
		}
		v := ""
		if i < len(variants) {
			v = strings.TrimSpace(variants[i])
		}
		id := l
		if v != "" {
			id += "-" + v
		}
		for n, base := 2, id; ids[id]; n++ {
			id = fmt.Sprintf("%s-%d", base, n)
		}
		ids[id] = true
		sources.Append(jsonx.Obj("id", id, "kind", "xkb", "layout", l, "variant", v, "engine", ""))
	}
	if len(sources.Items) == 0 {
		return []string{"Input.keyboard.layout was empty: Input.keyboard.sources starts from its default"}
	}
	keyboard.Set("sources", sources)
	return []string{fmt.Sprintf("Input.keyboard.layout and variant became Input.keyboard.sources: %d keyboard layout(s)", len(sources.Items))}
}
