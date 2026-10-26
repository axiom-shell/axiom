package clipboard

import (
	"bytes"
	"context"
	"image"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// offer is a selection held in memory.
type offer struct {
	mimes []string
	data  map[string]string
}

func (o *offer) Mimes() []string { return o.mimes }
func (o *offer) Receive(_ context.Context, mime string, max int, _ time.Duration) ([]byte, error) {
	d := o.data[mime]
	if len(d) > max {
		return nil, os.ErrInvalid
	}
	return []byte(d), nil
}

func text(s string) *offer {
	return &offer{mimes: []string{"text/plain;charset=utf-8", "text/plain"}, data: map[string]string{"text/plain;charset=utf-8": s}}
}

func pngOf(t *testing.T, w, h int) string {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewRGBA(image.Rect(0, 0, w, h))); err != nil {
		t.Fatal(err)
	}
	return b.String()
}

type harness struct {
	h   *History
	dir string
	mu  sync.Mutex
	set []string // the mimes of each Set
	got map[string][]byte
}

func newHistory(t *testing.T, max int) *harness {
	t.Helper()
	x := &harness{dir: filepath.Join(t.TempDir(), "axiom", "clipboard")}
	x.h = New(Options{Dir: x.dir, Set: func(mimes []string, data map[string][]byte) error {
		x.mu.Lock()
		defer x.mu.Unlock()
		x.set, x.got = mimes, data
		return nil
	}})
	x.h.Configure(true, max)
	return x
}

// rec records synchronously.
func (x *harness) rec(o Offer) { x.h.record(context.Background(), o) }

func texts(es []Entry) []string {
	var out []string
	for _, e := range es {
		out = append(out, e.Text)
	}
	return out
}

func TestRecordsTextNewestFirstDeduplicatedAndCapped(t *testing.T) {
	t.Parallel()
	x := newHistory(t, 3)
	for _, s := range []string{"one", "two", "one", "three", "four", "  ", ""} {
		x.rec(text(s))
	}
	if got := strings.Join(texts(x.h.Entries()), ","); got != "four,three,one" {
		t.Errorf("entries %s", got)
	}
	long := strings.Repeat("é", PreviewLength+5)
	x.rec(text(long))
	e := x.h.Entries()[0]
	if len([]rune(e.Text)) != PreviewLength {
		t.Errorf("preview of %d characters", len([]rune(e.Text)))
	}
	if whole, _ := x.h.Text(e.ID); whole != long {
		t.Error("the whole text isn't kept")
	}
	x.rec(text(strings.Repeat("x", MaxText+1)))
	if x.h.Entries()[0].ID != e.ID {
		t.Error("an over-long clip was recorded")
	}
}

func TestSkipsSecrets(t *testing.T) {
	t.Parallel()
	x := newHistory(t, 10)
	secret := text("hunter2")
	secret.mimes = append(secret.mimes, secretMime)
	secret.data[secretMime] = "secret\n"
	x.rec(secret)
	if len(x.h.Entries()) != 0 {
		t.Error("a secret was recorded")
	}
	other := text("fine")
	other.mimes = append(other.mimes, secretMime)
	other.data[secretMime] = "public"
	x.rec(other)
	if len(x.h.Entries()) != 1 {
		t.Error("a clip marked public wasn't recorded")
	}
}

func TestImagesAndImageHTML(t *testing.T) {
	t.Parallel()
	x := newHistory(t, 10)
	img := pngOf(t, 12, 7)
	browser := &offer{mimes: []string{"text/html", "image/png"}, data: map[string]string{"image/png": img, "text/html": `<img src="https://x/y.png">`}}
	x.rec(browser)
	e := x.h.Entries()[0]
	if e.Format != "png" || e.Dimensions != "12x7" || !strings.HasSuffix(e.Size, " B") {
		t.Fatalf("entry %+v", e)
	}
	if data, err := os.ReadFile(e.Image); err != nil || string(data) != img {
		t.Fatalf("image file %v", err)
	}
	info, _ := os.Stat(e.Image)
	dir, _ := os.Stat(x.dir)
	if info.Mode().Perm() != 0o600 || dir.Mode().Perm() != 0o700 {
		t.Errorf("modes %v %v", info.Mode().Perm(), dir.Mode().Perm())
	}
	// The same image again moves to the top, its old file gone
	x.rec(text("between"))
	x.rec(browser)
	es := x.h.Entries()
	if len(es) != 2 || es[0].Format != "png" {
		t.Fatalf("entries %+v", es)
	}
	if _, err := os.Stat(e.Image); err == nil && e.Image != es[0].Image {
		t.Error("the replaced image's file stayed")
	}
	// HTML alone that is just an image
	x.rec(&offer{mimes: []string{"text/html"}, data: map[string]string{"text/html": `<meta charset="utf-8"><img src="https://example.com/a.webp" alt="">`}})
	if h := x.h.Entries()[0]; !h.HTML || h.Image != "https://example.com/a.webp" {
		t.Errorf("html %+v", h)
	}
	// Other HTML alone isn't kept
	x.rec(&offer{mimes: []string{"text/html"}, data: map[string]string{"text/html": `<p>hi</p>`}})
	if len(x.h.Entries()) != 3 {
		t.Error("plain HTML was recorded")
	}
}

func TestCopyBackAndFiles(t *testing.T) {
	t.Parallel()
	x := newHistory(t, 10)
	x.rec(text("copied"))
	if err := x.h.Copy(x.h.Entries()[0].ID); err != nil {
		t.Fatal(err)
	}
	if x.set[0] != "text/plain;charset=utf-8" || string(x.got["text/plain"]) != "copied" {
		t.Errorf("set %v %q", x.set, x.got["text/plain"])
	}
	img := pngOf(t, 2, 2)
	x.rec(&offer{mimes: []string{"image/png"}, data: map[string]string{"image/png": img}})
	if err := x.h.Copy(x.h.Entries()[0].ID); err != nil || x.set[0] != "image/png" || string(x.got["image/png"]) != img {
		t.Errorf("image copy %v %v", err, x.set)
	}
	path := filepath.Join(t.TempDir(), "shot.png")
	os.WriteFile(path, []byte(img), 0o600)
	if err := x.h.CopyFile(path, "image/png"); err != nil || string(x.got["image/png"]) != img {
		t.Errorf("file copy %v", err)
	}
	if err := x.h.Copy("nope"); err == nil {
		t.Error("copied a clip that isn't there")
	}
}

func TestSaveTheCurrentSelection(t *testing.T) {
	t.Parallel()
	img := pngOf(t, 3, 3)
	cur := &offer{mimes: []string{"text/plain", "image/jpeg", "image/png"}, data: map[string]string{"image/png": img, "image/jpeg": "jpeg"}}
	h := New(Options{Current: func() Offer { return cur }})
	path := filepath.Join(t.TempDir(), "chat", "attachments", "a.png")
	mime, err := h.Save(context.Background(), []string{"image/png", "image/jpeg"}, path)
	if err != nil || mime != "image/png" {
		t.Fatalf("saved %q, %v", mime, err)
	}
	if data, _ := os.ReadFile(path); string(data) != img {
		t.Error("wrong bytes")
	}
	if _, err := h.Save(context.Background(), []string{"image/gif"}, path); err == nil {
		t.Error("saved a type the clipboard doesn't hold")
	}
}

func TestTurningOffForgetsEverything(t *testing.T) {
	t.Parallel()
	x := newHistory(t, 10)
	x.rec(&offer{mimes: []string{"image/png"}, data: map[string]string{"image/png": pngOf(t, 1, 1)}})
	x.rec(text("a"))
	x.h.Configure(false, 10)
	if len(x.h.Entries()) != 0 {
		t.Error("entries kept")
	}
	if files, _ := os.ReadDir(x.dir); len(files) != 0 {
		t.Errorf("%d files kept", len(files))
	}
	x.rec(text("b"))
	if len(x.h.Entries()) != 0 {
		t.Error("recorded while off")
	}
}

func TestHumanSize(t *testing.T) {
	t.Parallel()
	for n, want := range map[int]string{512: "512 B", 2048: "2.0 KiB", 3 << 20: "3.0 MiB"} {
		if got := humanSize(n); got != want {
			t.Errorf("%d: %s", n, got)
		}
	}
}
