package chat

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/command"
)

// Where a provider's key comes from, in the order looked: SecretsManager
// stores keys in the keyring or the file, and the environment wins over
// both.
const (
	SourceUnneeded = "unneeded" // auth "none"
	SourceEnv      = "env"      // the provider's keyEnv variable
	SourceKeyring  = "keyring"  // secret-tool: service axiom provider <id>
	SourceFile     = "file"     // secrets.json, under the provider's id
	SourceNone     = "none"
)

// key is the provider's key and where it came from ("" with unneeded or
// none). Only a cancelled ctx is an error: a keyring that doesn't answer
// is one without the key.
func (s *Service) key(ctx context.Context, p Provider) (string, string, error) {
	if p.Auth == "none" {
		return "", SourceUnneeded, nil
	}
	opts := s.o.Command()
	if p.KeyEnv != "" {
		if v := lookupEnv(opts.Env, p.KeyEnv); v != "" {
			return v, SourceEnv, nil
		}
	}
	out, err := command.Run(ctx, opts, []string{s.o.SecretTool, "lookup", "service", "axiom", "provider", p.ID}, nil)
	if ctx.Err() != nil {
		return "", "", ctx.Err()
	}
	if key := strings.TrimSpace(out.Stdout); err == nil && out.ExitCode == 0 && key != "" {
		return key, SourceKeyring, nil
	}
	if key := s.fileSecret(p.ID); key != "" {
		return key, SourceFile, nil
	}
	return "", SourceNone, nil
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

// fileSecret is the provider's key in secrets.json ({ "<id>": "…" }; the
// other scopes' are "<scope>:<id>"), "" without one
func (s *Service) fileSecret(id string) string {
	data, err := os.ReadFile(filepath.Join(s.o.StateDir, "secrets.json"))
	if err != nil {
		return ""
	}
	var secrets map[string]any
	if err := json.Unmarshal(data, &secrets); err != nil {
		s.o.Log.Warn("secrets.json doesn't parse", "err", err)
		return ""
	}
	key, _ := secrets[id].(string)
	return strings.TrimSpace(key)
}

// StatusRequest is the providers to say the key source of.
type StatusRequest struct {
	Providers []Provider `json:"providers"`
}

// StatusResult is each provider's key source (Source*), by id.
type StatusResult struct {
	Statuses map[string]string `json:"statuses"`
}

// Status says where each provider's key comes from, for the settings
// card and the chat's "add a key" hints, without the key leaving here.
func (s *Service) Status(ctx context.Context, r StatusRequest) (StatusResult, error) {
	out := StatusResult{Statuses: map[string]string{}}
	for _, p := range r.Providers {
		_, source, err := s.key(ctx, p)
		if err != nil {
			return StatusResult{}, err
		}
		out.Statuses[p.ID] = source
	}
	return out, nil
}
