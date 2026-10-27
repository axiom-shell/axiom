// Package secrets is where the secrets that never go in config.json live
// (SecretsManager): chat API keys (scope "provider") and calendar
// passwords (scope "calendar"). A secret is in the keyring (the Secret
// Service, through secret-tool: service axiom <scope> <id>) or, where
// none answers, in $XDG_STATE_HOME/axiom/secrets.json (mode 600; a
// provider's key under its bare id, as before scopes, any other under
// "<scope>:<id>"). Packages chat and calendar look their secrets up here
// themselves, so none passes through QML; the shell only stores and
// clears them (secrets.set, secrets.clear) and asks where they are.
// Secrets reach secret-tool through stdin, never argv, and are never
// logged.
package secrets

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/command"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Where a secret is.
const (
	SourceKeyring = "keyring"
	SourceFile    = "file"
	SourceNone    = "none"
)

// scopes are the kinds of secret kept
var scopes = map[string]bool{"provider": true, "calendar": true}

// Options are where secrets are kept; zero values are the real ones (only
// StateDir must be given).
type Options struct {
	// StateDir holds secrets.json
	StateDir string
	// Command is how secret-tool runs
	Command    func() command.Options
	SecretTool string
	Log        *slog.Logger
}

// Store reads and writes the secrets.
type Store struct {
	o  Options
	mu sync.Mutex // secrets.json's read, merge and rewrite
}

// New makes the store.
func New(o Options) *Store {
	if o.Command == nil {
		o.Command = func() command.Options { return command.Options{} }
	}
	if o.SecretTool == "" {
		o.SecretTool = "secret-tool"
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Store{o: o}
}

// Lookup is the secret and where it is ("" and SourceNone without one):
// the keyring first, then the file. Only a cancelled ctx is an error: a
// keyring that doesn't answer is one without the secret.
func (s *Store) Lookup(ctx context.Context, scope, id string) (string, string, error) {
	out, err := s.run(ctx, nil, "lookup", "service", "axiom", scope, id)
	if ctx.Err() != nil {
		return "", "", ctx.Err()
	}
	if v := strings.TrimSpace(out.Stdout); err == nil && out.ExitCode == 0 && v != "" {
		return v, SourceKeyring, nil
	}
	secrets, err := s.read()
	if err != nil {
		s.o.Log.Warn("secrets.json can't be read", "err", err)
	}
	v, _ := secrets[slot(scope, id)].(string)
	if v = strings.TrimSpace(v); v != "" {
		return v, SourceFile, nil
	}
	return "", SourceNone, nil
}

// Keyring says whether a Secret Service answers: a lookup of something
// never stored fails quietly (exit 1, nothing on stderr) when one does,
// and complains when none does.
func (s *Store) Keyring(ctx context.Context) bool {
	out, err := s.run(ctx, nil, "lookup", "service", "axiom-probe", "probe", "probe")
	return err == nil && strings.TrimSpace(out.Stderr) == ""
}

// Set stores a secret (label names it in the keyring) and says where: the
// keyring, else the file. An empty one clears it.
func (s *Store) Set(ctx context.Context, scope, id, label, value string) (string, error) {
	if err := check(scope, id); err != nil {
		return "", err
	}
	value = strings.TrimSpace(value)
	if value == "" {
		return SourceNone, s.Clear(ctx, scope, id)
	}
	out, err := s.run(ctx, &value, "store", "--label=Axiom: "+label, "service", "axiom", scope, id)
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	if err == nil && out.ExitCode == 0 {
		// One place per secret: the file's copy would outlive a later clear
		// (one in a file that can't be read is never looked up anyway)
		if err := s.write(slot(scope, id), ""); err != nil {
			s.o.Log.Warn("secrets.json's copy can't be dropped", "err", err)
		}
		return SourceKeyring, nil
	}
	s.o.Log.Info("no keyring took the secret; saving it to secrets.json", "slot", slot(scope, id))
	return SourceFile, s.write(slot(scope, id), value)
}

// Clear removes a secret from the keyring and the file.
func (s *Store) Clear(ctx context.Context, scope, id string) error {
	if err := check(scope, id); err != nil {
		return err
	}
	// A keyring that doesn't answer holds nothing to clear
	s.run(ctx, nil, "clear", "service", "axiom", scope, id)
	if ctx.Err() != nil {
		return ctx.Err()
	}
	return s.write(slot(scope, id), "")
}

func check(scope, id string) error {
	if !scopes[scope] || id == "" {
		return axerr.New(axerr.BadRequest, "unknown secret %q %q", scope, id)
	}
	return nil
}

// slot is where a secret sits in the file
func slot(scope, id string) string {
	if scope == "provider" {
		return id
	}
	return scope + ":" + id
}

func (s *Store) run(ctx context.Context, input *string, args ...string) (command.Result, error) {
	return command.Run(ctx, s.o.Command(), append([]string{s.o.SecretTool}, args...), input)
}

func (s *Store) path() string { return filepath.Join(s.o.StateDir, "secrets.json") }

// read is secrets.json (empty without one; an error when it can't be read
// or doesn't parse, so a write never replaces what's there)
func (s *Store) read() (map[string]any, error) {
	secrets := map[string]any{}
	data, err := os.ReadFile(s.path())
	if errors.Is(err, fs.ErrNotExist) {
		return secrets, nil
	} else if err != nil {
		return secrets, axerr.Wrap(axerr.Unavailable, err, "reading %s", s.path())
	}
	if err := json.Unmarshal(data, &secrets); err != nil {
		return map[string]any{}, axerr.Wrap(axerr.Unavailable, err, "%s doesn't parse", s.path())
	}
	return secrets, nil
}

// write sets one slot of secrets.json ("" removes it), atomically and
// mode 600; nothing is written when it wouldn't change
func (s *Store) write(key, value string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	secrets, err := s.read()
	if err != nil {
		return err
	}
	if old, ok := secrets[key]; (value == "" && !ok) || (ok && old == value) {
		return nil
	}
	if value == "" {
		delete(secrets, key)
	} else {
		secrets[key] = value
	}
	data, err := json.MarshalIndent(secrets, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(s.o.StateDir, 0o700); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "creating %s", s.o.StateDir)
	}
	// An existing file keeps its mode through a rewrite: fix it first
	if err := os.Chmod(s.path(), 0o600); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return axerr.Wrap(axerr.Unavailable, err, "securing %s", s.path())
	}
	return fsx.WriteFile(s.path(), data, 0o600)
}
