// Package fetch downloads an official release's files (package release
// says which and from where) and checks each against the release's
// SHA256SUMS before handing it over: a v* release's binary, or the edge
// prerelease's binary and the commit it was built from.
package fetch

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/release"
)

// How long a listing and a binary may take to download.
const (
	sumsTimeout   = time.Minute
	binaryTimeout = 5 * time.Minute
)

var (
	// ErrMissing: the release, or the file in it, isn't there (no such
	// tag, no binary for this machine, offline). Callers fall back.
	ErrMissing = errors.New("not published")
	// ErrMismatch: a file doesn't match its release's SHA256SUMS (or
	// isn't listed). Never used; a caller may fall back but says why.
	ErrMismatch = errors.New("doesn't match its SHA256SUMS")
)

// Options configures a Fetcher.
type Options struct {
	// Base replaces release.Official (tests serve their own releases).
	Base string
	// Client replaces http.DefaultClient.
	Client *http.Client
}

// Fetcher downloads from one releases url.
type Fetcher struct {
	base   string
	client *http.Client
}

// New is a Fetcher for opts.
func New(opts Options) *Fetcher {
	f := &Fetcher{base: opts.Base, client: opts.Client}
	if f.base == "" {
		f.base = release.Official
	}
	if f.client == nil {
		f.client = http.DefaultClient
	}
	return f
}

// SumsURL is the url of tag's SHA256SUMS, which root fetches itself to
// check a binary handed to it.
func (f *Fetcher) SumsURL(tag string) (string, bool) {
	return release.URL(f.base, tag, release.Sums)
}

// Binary is tag's prebuilt binary for goarch, checked against the
// release's SHA256SUMS. ErrMissing when there's none to take, ErrMismatch
// when what was downloaded isn't what the release lists.
func (f *Fetcher) Binary(ctx context.Context, tag, goarch string) ([]byte, error) {
	asset, ok := release.Asset(goarch)
	if !ok {
		return nil, fmt.Errorf("%s: no binary for %s: %w", tag, goarch, ErrMissing)
	}
	return f.checked(ctx, tag, asset, binaryTimeout)
}

// EdgeCommit is the commit the edge prerelease was built from, its
// COMMIT checked against its SHA256SUMS like any of its files.
func (f *Fetcher) EdgeCommit(ctx context.Context) (string, error) {
	data, err := f.checked(ctx, release.Edge, release.Commit, sumsTimeout)
	if err != nil {
		return "", err
	}
	commit, ok := release.ParseCommit(string(data))
	if !ok {
		return "", fmt.Errorf("%s's %s isn't a commit: %w", release.Edge, release.Commit, ErrMismatch)
	}
	return commit, nil
}

// checked is one of tag's files, downloaded after its SHA256SUMS and
// matched against it.
func (f *Fetcher) checked(ctx context.Context, tag, file string, timeout time.Duration) ([]byte, error) {
	sumsURL, ok := f.SumsURL(tag)
	fileURL, _ := release.URL(f.base, tag, file)
	if !ok {
		return nil, fmt.Errorf("%q isn't a release tag: %w", tag, ErrMissing)
	}
	sums, err := f.get(ctx, sumsURL, sumsTimeout)
	if err != nil {
		return nil, err
	}
	data, err := f.get(ctx, fileURL, timeout)
	if err != nil {
		return nil, err
	}
	want := release.SumFor(string(sums), file)
	if got := fmt.Sprintf("%x", sha256.Sum256(data)); want == "" || !strings.EqualFold(want, got) {
		return nil, fmt.Errorf("the %s release's %s %w", tag, file, ErrMismatch)
	}
	return data, nil
}

// get is a url's body; any failure to get it is ErrMissing.
func (f *Fetcher) get(ctx context.Context, url string, timeout time.Duration) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("%s: %w: %w", url, err, ErrMissing)
	}
	resp, err := f.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", err, ErrMissing)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s: %w", url, resp.Status, ErrMissing)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%s: %w: %w", url, err, ErrMissing)
	}
	return data, nil
}
