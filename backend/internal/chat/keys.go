package chat

import (
	"context"
	"os"
	"strings"
)

// Where a provider's key comes from, in the order looked: the environment
// wins over what's stored (package secrets: the keyring, then the file).
const (
	SourceUnneeded = "unneeded" // auth "none"
	SourceEnv      = "env"      // the provider's keyEnv variable
)

// key is the provider's key and where it came from ("" with unneeded or
// none). Only a cancelled ctx is an error.
func (s *Service) key(ctx context.Context, p Provider) (string, string, error) {
	if p.Auth == "none" {
		return "", SourceUnneeded, nil
	}
	if p.KeyEnv != "" {
		if v := lookupEnv(s.o.Command().Env, p.KeyEnv); v != "" {
			return v, SourceEnv, nil
		}
	}
	return s.o.Secrets.Lookup(ctx, "provider", p.ID)
}

// lookupEnv reads name from env (nil: the daemon's own environment); the
// last of a repeated name wins, as in exec
func lookupEnv(env []string, name string) string {
	if env == nil {
		return os.Getenv(name)
	}
	value := ""
	for _, kv := range env {
		if k, v, ok := strings.Cut(kv, "="); ok && k == name {
			value = v
		}
	}
	return value
}

// StatusRequest is the providers to say the key source of.
type StatusRequest struct {
	Providers []Provider `json:"providers"`
}

// Status says where each provider's key comes from (Source*, or
// secrets.Source*), by id, for the settings card and the chat's "add a
// key" hints, without the key leaving here.
func (s *Service) Status(ctx context.Context, r StatusRequest) (map[string]string, error) {
	out := map[string]string{}
	for _, p := range r.Providers {
		_, source, err := s.key(ctx, p)
		if err != nil {
			return nil, err
		}
		out[p.ID] = source
	}
	return out, nil
}
