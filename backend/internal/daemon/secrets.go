package daemon

import (
	"context"

	"github.com/axiom-shell/axiom/backend/internal/chat"
	"github.com/axiom-shell/axiom/backend/internal/rpc"
	"github.com/axiom-shell/axiom/backend/internal/secrets"
)

// secretsPart: SecretsManager's store (the keyring, else secrets.json),
// which packages chat and calendar read themselves: the shell stores and
// clears a secret and asks where each one is, never reading one back.
func (d *Daemon) secretsPart() part {
	return part{name: "secrets", methods: d.secretsMethods}
}

// secretStore is the user's secrets, as every part reading them opens it
func (d *Daemon) secretStore(log string) *secrets.Store {
	return secrets.New(secrets.Options{StateDir: d.dirs.State, Command: d.commandOptions, Log: d.opts.Log.With("part", log)})
}

func (d *Daemon) secretsMethods(reg *rpc.Registry) {
	store := d.secretStore("secrets")
	keys := chat.New(chat.Options{Secrets: store, Command: d.commandOptions})
	type statusParams struct {
		Providers []chat.Provider `json:"providers"`
		// Calendar accounts' ids
		Calendars []string `json:"calendars"`
	}
	type statusResult struct {
		// Whether a Secret Service answers (else secrets go to the file)
		Keyring bool `json:"keyring"`
		// By provider id and "calendar:<id>": chat.Source* or secrets.Source*
		Statuses map[string]string `json:"statuses"`
	}
	type setParams struct {
		Scope string `json:"scope"` // "provider" or "calendar"
		ID    string `json:"id"`
		// Names it in the keyring
		Label string `json:"label"`
		// "" clears it
		Value string `json:"value"`
	}
	type setResult struct {
		Source string `json:"source"`
	}
	type clearParams struct {
		Scope string `json:"scope"`
		ID    string `json:"id"`
	}
	rpc.Handle(reg, "secrets.status", func(ctx context.Context, c *rpc.Conn, p statusParams) (statusResult, error) {
		statuses, err := keys.Status(ctx, chat.StatusRequest{Providers: p.Providers})
		if err != nil {
			return statusResult{}, err
		}
		for _, id := range p.Calendars {
			_, source, err := store.Lookup(ctx, "calendar", id)
			if err != nil {
				return statusResult{}, err
			}
			statuses["calendar:"+id] = source
		}
		return statusResult{Keyring: store.Keyring(ctx), Statuses: statuses}, nil
	})
	rpc.Handle(reg, "secrets.set", func(ctx context.Context, c *rpc.Conn, p setParams) (setResult, error) {
		source, err := store.Set(ctx, p.Scope, p.ID, p.Label, p.Value)
		return setResult{Source: source}, err
	})
	rpc.Handle(reg, "secrets.clear", func(ctx context.Context, c *rpc.Conn, p clearParams) (struct{}, error) {
		return struct{}{}, store.Clear(ctx, p.Scope, p.ID)
	})
}
