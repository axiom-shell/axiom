// Package media fetches a track's album art for the shell (`media.art`,
// MediaManager): an http(s) URL downloaded, or a file:// one copied, into
// the session's art folder, where the shell's images read it.
package media

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

const (
	timeout = 15 * time.Second
	// Art is a picture, never more: a bigger answer isn't kept
	maxSize = 32 << 20
)

// Options are where art goes and how it's fetched; a zero Client is
// http.DefaultClient.
type Options struct {
	// Dir is the only folder art may be written to
	// ($XDG_RUNTIME_DIR/axiom/media-art)
	Dir    string
	Client *http.Client
}

// ArtDir is the art folder for runtimeDir ($XDG_RUNTIME_DIR), the shell's
// Paths.runtimePath + "media-art/".
func ArtDir(runtimeDir string) string {
	if runtimeDir == "" {
		return ""
	}
	return filepath.Join(runtimeDir, "axiom", "media-art")
}

// Art puts the art at src into path, which must be a file directly in
// o.Dir. A file already there (and not empty) is kept: the shell names art
// by its URL. It lands in path.part and is renamed, so an interrupted
// fetch is never taken for art.
func Art(ctx context.Context, o Options, src, path string) error {
	if o.Dir == "" || filepath.Dir(filepath.Clean(path)) != filepath.Clean(o.Dir) || filepath.Base(path) == "." {
		return axerr.New(axerr.Refused, "media.art: %q is not in %s", path, o.Dir)
	}
	if fi, err := os.Stat(path); err == nil && fi.Mode().IsRegular() && fi.Size() > 0 {
		return nil
	}
	u, err := url.Parse(src)
	if err != nil {
		return axerr.Wrap(axerr.BadRequest, err, "media.art: bad url")
	}
	if err := os.MkdirAll(o.Dir, 0o700); err != nil {
		return axerr.Wrap(axerr.Internal, err, "media.art")
	}
	var body io.ReadCloser
	switch u.Scheme {
	case "http", "https":
		body, err = download(ctx, o, src)
	case "file":
		body, err = os.Open(u.Path)
	default:
		return axerr.New(axerr.BadRequest, "media.art: can't fetch %q", u.Scheme)
	}
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "media.art")
	}
	defer body.Close()
	part := path + ".part"
	f, err := os.OpenFile(part, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return axerr.Wrap(axerr.Internal, err, "media.art")
	}
	n, err := io.Copy(f, io.LimitReader(body, maxSize+1))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil && n > maxSize {
		err = fmt.Errorf("larger than %d MB", maxSize>>20)
	}
	if err == nil && n == 0 {
		err = fmt.Errorf("empty")
	}
	if err == nil {
		err = os.Rename(part, path)
	}
	if err != nil {
		os.Remove(part)
		return axerr.Wrap(axerr.Unavailable, err, "media.art")
	}
	return nil
}

func download(ctx context.Context, o Options, src string) (io.ReadCloser, error) {
	client := o.Client
	if client == nil {
		client = http.DefaultClient
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src, nil)
	if err != nil {
		cancel()
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		cancel()
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		resp.Body.Close()
		cancel()
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return cancelOnClose{resp.Body, cancel}, nil
}

// cancelOnClose ends the request's timeout with its body
type cancelOnClose struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (c cancelOnClose) Close() error {
	err := c.ReadCloser.Close()
	c.cancel()
	return err
}
