package daemon

import (
	"context"
	stdimage "image"
	"image/color"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
)

func backdropFixture(t *testing.T) (*backdropPart, *atomic.Int32, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "w.png")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	b := newBackdropPart()
	var decodes atomic.Int32
	b.decode = func(string) (stdimage.Image, error) {
		decodes.Add(1)
		img := stdimage.NewNRGBA(stdimage.Rect(0, 0, 10, 10))
		for i := range img.Pix {
			img.Pix[i] = 255
		}
		img.SetNRGBA(0, 0, color.NRGBA{0, 0, 0, 255})
		return img, nil
	}
	return b, &decodes, path
}

func TestBackdropCache(t *testing.T) {
	b, decodes, path := backdropFixture(t)
	for range 3 {
		if _, err := b.grid(context.Background(), path); err != nil {
			t.Fatal(err)
		}
	}
	if decodes.Load() != 1 {
		t.Fatalf("%d decodes for one file", decodes.Load())
	}
	if err := os.WriteFile(path, []byte("xy"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := b.grid(context.Background(), path); err != nil {
		t.Fatal(err)
	}
	if decodes.Load() != 2 {
		t.Fatalf("%d decodes after the file changed", decodes.Load())
	}
}

func TestBackdropSharesADecode(t *testing.T) {
	b, decodes, path := backdropFixture(t)
	release := make(chan struct{})
	started := make(chan struct{})
	inner := b.decode
	b.decode = func(p string) (stdimage.Image, error) {
		close(started)
		<-release
		return inner(p)
	}
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := b.grid(context.Background(), path); err != nil {
				t.Error(err)
			}
		}()
	}
	<-started
	// the second ask joins the flight (or hits the cache): never a second decode
	close(release)
	wg.Wait()
	if decodes.Load() != 1 {
		t.Fatalf("%d decodes for two concurrent asks", decodes.Load())
	}
}

func TestBackdropMissingFile(t *testing.T) {
	b := newBackdropPart()
	if _, err := b.grid(context.Background(), filepath.Join(t.TempDir(), "none.png")); err == nil {
		t.Fatal("a missing file gave a grid")
	}
}
