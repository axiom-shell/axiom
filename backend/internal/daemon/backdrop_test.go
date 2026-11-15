package daemon

import (
	"context"
	"errors"
	stdimage "image"
	"image/color"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
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

func TestBackdropWaiterOutlivesCancelledLeader(t *testing.T) {
	b, _, path := backdropFixture(t)
	b.decodeSlot <- struct{}{}
	leaderCtx, cancel := context.WithCancel(context.Background())
	leaderErr := make(chan error, 1)
	go func() {
		_, err := b.grid(leaderCtx, path)
		leaderErr <- err
	}()
	for deadline := time.Now().Add(5 * time.Second); ; {
		b.mu.Lock()
		n := len(b.flights)
		b.mu.Unlock()
		if n == 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the leader never started a flight")
		}
		time.Sleep(time.Millisecond)
	}
	waiterErr := make(chan error, 1)
	go func() {
		_, err := b.grid(context.Background(), path)
		waiterErr <- err
	}()
	time.Sleep(20 * time.Millisecond)
	cancel()
	if err := <-leaderErr; !errors.Is(err, context.Canceled) {
		t.Fatalf("the leader returned %v", err)
	}
	<-b.decodeSlot
	select {
	case err := <-waiterErr:
		if err != nil {
			t.Fatalf("the waiter inherited %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the waiter never returned")
	}
}

func TestBackdropDecodePanic(t *testing.T) {
	b, _, path := backdropFixture(t)
	b.decode = func(string) (stdimage.Image, error) { panic("boom") }
	if _, err := b.grid(context.Background(), path); err == nil {
		t.Fatal("a panicking decode gave a grid")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_, err := b.grid(ctx, path)
	if err == nil || errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("the second ask returned %v", err)
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.flights) != 0 {
		t.Fatal("a flight was stranded")
	}
}

func TestBackdropMissingFile(t *testing.T) {
	b := newBackdropPart()
	if _, err := b.grid(context.Background(), filepath.Join(t.TempDir(), "none.png")); err == nil {
		t.Fatal("a missing file gave a grid")
	}
}
