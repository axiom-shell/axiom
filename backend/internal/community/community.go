// Package community downloads the community setups gallery's files for
// CommunitySetupsManager (`community.fetch`): the catalog, thumbnails,
// screenshots, and a setup's config, palette and wallpaper. Each file is
// checked against its sha256 when one is given and written atomically, so
// a half-downloaded or tampered file never lands; a destination already
// holding that sha256 is kept without downloading (the cache). Files are
// written only under the folders the daemon names, fetched only over
// http(s) (redirects too), and capped at 20 MB.
package community

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

const (
	maxSize = 20 << 20
	// timeout is one file's, its redirects and body included
	timeout = 60 * time.Second
	// parallel is how many files of one call download at once
	parallel = 4
)

// File is one download.
type File struct {
	URL  string `json:"url"`
	Dest string `json:"dest"`
	// The hex sha256 the file must have; "" takes it unchecked (the
	// catalog, whose own entries carry the others' hashes)
	SHA256 string `json:"sha256,omitempty"`
}

// Result is how one download went.
type Result struct {
	Dest string `json:"dest"`
	// Why it failed (English, for the log); "" when the file is in place
	Error string `json:"error,omitempty"`
}

// Options are where files may be written.
type Options struct {
	// Roots are the only folders (and their subfolders) a Dest may be in
	Roots []string
}

// Fetcher downloads files; it's safe for concurrent calls.
type Fetcher struct {
	roots  []string
	client *http.Client
}

// New returns a Fetcher.
func New(opts Options) *Fetcher {
	client := &http.Client{CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if !webScheme(req.URL) {
			return fmt.Errorf("redirected to %s, which isn't http(s)", req.URL.Scheme)
		}
		if len(via) >= 10 {
			return errors.New("too many redirects")
		}
		return nil
	}}
	return &Fetcher{roots: opts.Roots, client: client}
}

// Fetch downloads files, a few at once, and returns each one's result in
// their order.
func (f *Fetcher) Fetch(ctx context.Context, files []File) []Result {
	results := make([]Result, len(files))
	slots := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, file := range files {
		results[i].Dest = file.Dest
		wg.Add(1)
		go func() {
			defer wg.Done()
			slots <- struct{}{}
			defer func() { <-slots }()
			if err := f.one(ctx, file); err != nil {
				results[i].Error = err.Error()
			}
		}()
	}
	wg.Wait()
	return results
}

func (f *Fetcher) one(ctx context.Context, file File) error {
	if !Within(f.roots, file.Dest) {
		return errors.New("not a folder community files go to")
	}
	want := strings.ToLower(file.SHA256)
	if want != "" {
		if data, err := os.ReadFile(file.Dest); err == nil && sum(data) == want {
			return nil
		}
	}
	u, err := url.Parse(file.URL)
	if err != nil || !webScheme(u) {
		return errors.New("only http(s) is fetched")
	}
	data, err := f.download(ctx, file.URL)
	if err != nil {
		return err
	}
	if want != "" && sum(data) != want {
		return errors.New("checksum mismatch")
	}
	if err := os.MkdirAll(filepath.Dir(file.Dest), 0o755); err != nil {
		return errors.New("can't make its folder")
	}
	if err := fsx.WriteFile(file.Dest, data, 0o644); err != nil {
		return fmt.Errorf("can't write it: %w", err)
	}
	return nil
}

func (f *Fetcher) download(ctx context.Context, src string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src, nil)
	if err != nil {
		return nil, err
	}
	resp, err := f.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if resp.ContentLength > maxSize {
		return nil, fmt.Errorf("larger than %d MB", maxSize>>20)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxSize+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxSize {
		return nil, fmt.Errorf("larger than %d MB", maxSize>>20)
	}
	return data, nil
}

// Within: dest is an absolute file path inside one of roots.
func Within(roots []string, dest string) bool {
	if !filepath.IsAbs(dest) {
		return false
	}
	for _, root := range roots {
		rel, err := filepath.Rel(filepath.Clean(root), filepath.Clean(dest))
		if err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, "../") {
			return true
		}
	}
	return false
}

func webScheme(u *url.URL) bool { return u.Scheme == "http" || u.Scheme == "https" }

func sum(data []byte) string {
	s := sha256.Sum256(data)
	return hex.EncodeToString(s[:])
}
