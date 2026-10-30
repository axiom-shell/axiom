package saved

import (
	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/share"
)

// Shared is a shared file as Export would write it again (`axiom config
// share`): what the community setups' CI admits.
type Shared struct {
	// Loaded is the file loaded as an import is (any version, converted)
	Loaded config.Loaded
	// Export is the file as Export writes it: its header, then its look,
	// only what differs from the defaults
	Export *jsonx.Object
	// Dropped is what the file holds that Export leaves out, by scope
	Dropped []share.Drop
}

// Share loads parsed (a shared file, named name) through p and picks it as
// Export would: its look, never a personal part, a command, a machine
// value or a takeover setting. places: a monitor already named by its
// place (#2, @primary, *) is kept, a connector name left out. A file that
// isn't valid is an invalid_config error listing its problems.
func Share(p config.Pipeline, parsed any, name string, places bool) (Shared, error) {
	// A newer one is refused by the pipeline, naming its version
	obj, err := versioned(parsed, name)
	if err != nil {
		return Shared{}, err
	}
	loaded, err := p.Load(withoutHeader(obj))
	if err != nil {
		return Shared{}, err
	}
	if len(loaded.Errors) > 0 {
		return Shared{}, &axerr.Error{Kind: axerr.InvalidConfig, Message: name + " isn't a valid config", Issues: issuesOf(loaded.Errors)}
	}
	var monitors share.Monitors
	if places {
		// None connected: only places stay
		monitors = share.Monitors{}
	}
	sch := p.Schema()
	h := header(obj)
	out := envelope(h.Title, h.Description, "")
	body := share.Sparse(sch, share.Pick(sch, loaded.Config, nil, monitors)).(*jsonx.Object)
	for _, k := range body.Keys() {
		out.Set(k, body.Value(k))
	}
	return Shared{
		Loaded:  loaded,
		Export:  out,
		Dropped: share.Dropped(sch, share.Sparse(sch, loaded.Config), nil, monitors),
	}, nil
}
