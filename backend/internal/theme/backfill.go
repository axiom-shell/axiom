package theme

import (
	"maps"
	"os"
	"slices"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/footprint"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/theme/integrations"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Existing are file rows (Prior absent) for the files an earlier axiom's
// integrations left: each existing file at a path of an integration of the
// table, but a main config the app needs to load the colors (IfMissing:
// the user's from then on). The ledger's backfill marks them inferred.
func (in *Integrator) Existing() []footprint.Row {
	b := xdg.ResolveBases(in.opts.Getenv)
	var rows []footprint.Row
	for _, key := range slices.Sorted(maps.Keys(integrations.Table)) {
		integ := integrations.Table[key]
		r := &run{Integrator: in, key: key, dirs: integrations.Dirs{Home: b.Home, Config: b.Config, State: b.State, Data: b.Data}}
		places := []string{""}
		if integ.Each != nil || integ.Profiles {
			places = r.places(integ)
		}
		for _, each := range places {
			d := r.dirs
			d.Each = each
			for _, f := range integ.Files {
				if f.IfMissing || strings.HasPrefix(f.Path, "{each}") != (each != "") {
					continue
				}
				path := d.Expand(f.Path)
				if _, err := os.Lstat(path); err == nil {
					// The file a write would reach, as writeFile records it
					if target, err := fsx.Resolve(path); err == nil {
						path = target
					}
					if slices.ContainsFunc(rows, func(r footprint.Row) bool { return r.Target == path }) {
						continue
					}
					rows = append(rows, footprint.Row{Kind: footprint.KindFile, Target: path, Owner: "ThemeIntegrations." + key, Prior: footprint.Absent()})
				}
			}
		}
	}
	return rows
}
