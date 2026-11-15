package daemon

import (
	"context"
	"errors"
	stdimage "image"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/theme"
	"github.com/axiom-shell/axiom/backend/internal/theme/backdrop"
)

// backdropCacheSize is the grids kept (one per shown wallpaper, with room
// for a few screens and the last ones).
const backdropCacheSize = 8

// backdropKey identifies a wallpaper file as it is on disk: a file edited in
// place is a new key.
type backdropKey struct {
	path  string
	mtime time.Time
	size  int64
}

// backdropFlight is one decode in progress, shared by every ask for its key.
type backdropFlight struct {
	done chan struct{}
	grid backdrop.Grid
	err  error
}

// backdropPart is theme.backdrop's state: the grids of the wallpapers shown
// (an in-memory LRU, nothing written), the decodes in flight, and the one
// slot every full decode takes, theme.generate's included, so at most one
// full-resolution image is held at a time.
type backdropPart struct {
	// decodeSlot holds a token while an image is decoded
	decodeSlot chan struct{}
	// decode reads an image (theme.Open; a test replaces it)
	decode func(path string) (stdimage.Image, error)

	mu      sync.Mutex
	lru     []backdropKey // oldest first
	grids   map[backdropKey]backdrop.Grid
	flights map[backdropKey]*backdropFlight
}

func newBackdropPart() *backdropPart {
	return &backdropPart{
		decodeSlot: make(chan struct{}, 1),
		decode:     theme.Open,
		grids:      map[backdropKey]backdrop.Grid{},
		flights:    map[backdropKey]*backdropFlight{},
	}
}

// acquire takes the decode slot, or fails when ctx ends first.
func (b *backdropPart) acquire(ctx context.Context) error {
	select {
	case b.decodeSlot <- struct{}{}:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (b *backdropPart) release() { <-b.decodeSlot }

// grid is the wallpaper at path as a backdrop grid: from the cache, from the
// decode another ask already runs, or from a decode of its own.
func (b *backdropPart) grid(ctx context.Context, path string) (backdrop.Grid, error) {
	path, err := filepath.Abs(path)
	if err != nil {
		return backdrop.Grid{}, axerr.Wrap(axerr.BadRequest, err, "can't read the wallpaper")
	}
	info, err := os.Stat(path)
	if err != nil {
		kind := axerr.Unavailable
		if os.IsNotExist(err) {
			kind = axerr.NotFound
		}
		return backdrop.Grid{}, axerr.Wrap(kind, err, "can't read the wallpaper")
	}
	key := backdropKey{path, info.ModTime(), info.Size()}

	for {
		b.mu.Lock()
		if g, ok := b.grids[key]; ok {
			b.touch(key)
			b.mu.Unlock()
			return g, nil
		}
		if f, ok := b.flights[key]; ok {
			b.mu.Unlock()
			select {
			case <-f.done:
				// A cancelled leader's error is its own: ask again
				if f.err != nil && (errors.Is(f.err, context.Canceled) || errors.Is(f.err, context.DeadlineExceeded)) && ctx.Err() == nil {
					continue
				}
				return f.grid, f.err
			case <-ctx.Done():
				return backdrop.Grid{}, ctx.Err()
			}
		}
		f := &backdropFlight{done: make(chan struct{})}
		b.flights[key] = f
		b.mu.Unlock()

		func() {
			defer func() {
				if recover() != nil {
					f.grid, f.err = backdrop.Grid{}, axerr.New(axerr.Internal, "can't decode the wallpaper")
				}
				b.mu.Lock()
				delete(b.flights, key)
				if f.err == nil {
					b.grids[key] = f.grid
					b.lru = append(b.lru, key)
					for len(b.lru) > backdropCacheSize {
						delete(b.grids, b.lru[0])
						b.lru = b.lru[1:]
					}
				}
				b.mu.Unlock()
				close(f.done)
			}()
			f.grid, f.err = b.sample(ctx, path)
		}()
		return f.grid, f.err
	}
}

// touch makes key the newest (mu held).
func (b *backdropPart) touch(key backdropKey) {
	for i, k := range b.lru {
		if k == key {
			b.lru = append(append(b.lru[:i:i], b.lru[i+1:]...), key)
			return
		}
	}
}

func (b *backdropPart) sample(ctx context.Context, path string) (backdrop.Grid, error) {
	if err := b.acquire(ctx); err != nil {
		return backdrop.Grid{}, err
	}
	defer b.release()
	img, err := b.decode(path)
	if err != nil {
		return backdrop.Grid{}, err
	}
	return backdrop.Sample(img), nil
}
