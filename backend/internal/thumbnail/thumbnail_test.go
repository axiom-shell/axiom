package thumbnail

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"hash/crc32"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/filesearch"
)

// The test binary is its own child: `<test binary> thumbnail`
func TestMain(m *testing.M) {
	if len(os.Args) > 1 && os.Args[1] == ChildCommand {
		err := RunChild(context.Background(), os.Stdin)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
		os.Exit(ExitCode(err))
	}
	os.Exit(m.Run())
}

// The spec's own example
func TestHash(t *testing.T) {
	t.Parallel()
	if got := Hash("file:///home/jens/photos/me.png"); got != "c6ee772d9e49320e97ec29a7eb5b1697" {
		t.Errorf("hash %s", got)
	}
}

func writePNG(t *testing.T, path string, w, h int) {
	t.Helper()
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for x := range w {
		img.Set(x, 0, color.NRGBA{R: 255, A: 255})
	}
	var buf bytes.Buffer
	png.Encode(&buf, img)
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

// bomb is a PNG header claiming a huge image
func bomb() []byte {
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:], 20000)
	binary.BigEndian.PutUint32(ihdr[4:], 20000)
	ihdr[8], ihdr[9] = 8, 6
	out := []byte(pngSignature)
	out = binary.BigEndian.AppendUint32(out, 13)
	start := len(out)
	out = append(append(out, "IHDR"...), ihdr...)
	return binary.BigEndian.AppendUint32(out, crc32.ChecksumIEEE(out[start:]))
}

func TestGet(t *testing.T) {
	t.Parallel()
	files, cache := t.TempDir(), t.TempDir()
	photo := filepath.Join(files, "my photo.png")
	writePNG(t, photo, 300, 200)
	os.WriteFile(filepath.Join(files, "broken.png"), []byte("not a png"), 0o644)
	os.WriteFile(filepath.Join(files, "bomb.png"), bomb(), 0o644)
	os.WriteFile(filepath.Join(files, "icon.svg"), []byte("<svg/>"), 0o644)
	os.WriteFile(filepath.Join(files, "clip.mp4"), []byte("x"), 0o644)
	s := New(Options{CacheHome: cache, Exe: os.Args[0]})
	ctx := context.Background()

	res, err := s.Get(ctx, photo, "normal")
	uri := filesearch.FileURI(photo)
	want := filepath.Join(cache, "thumbnails", "normal", Hash(uri)+".png")
	if err != nil || res.Path != want {
		t.Fatalf("%+v %v, want %s", res, err, want)
	}
	info, _ := os.Stat(want)
	dir, _ := os.Stat(filepath.Dir(want))
	if info.Mode().Perm() != 0o600 || dir.Mode().Perm() != 0o700 {
		t.Errorf("modes %v %v", info.Mode(), dir.Mode())
	}
	data, _ := os.ReadFile(want)
	src, _ := os.Stat(photo)
	texts := Texts(data)
	if texts["Thumb::URI"] != uri || texts["Thumb::MTime"] != strconv.FormatInt(src.ModTime().Unix(), 10) || texts["Thumb::Size"] != strconv.FormatInt(src.Size(), 10) {
		t.Errorf("texts %v", texts)
	}
	if img, err := png.Decode(bytes.NewReader(data)); err != nil || img.Bounds().Dx() != 128 || img.Bounds().Dy() != 85 {
		t.Errorf("image %v %v", img.Bounds(), err)
	}

	// Found again without making it: a service that can't run its child
	cached := New(Options{CacheHome: cache, Exe: "/nonexistent"})
	if res, err := cached.Get(ctx, photo, "normal"); err != nil || res.Path != want {
		t.Errorf("cached: %+v %v", res, err)
	}
	// The file changed: no longer valid
	later := time.Now().Add(time.Hour)
	os.Chtimes(photo, later, later)
	if Valid(want, uri, later.Unix()) {
		t.Error("valid after the file changed")
	}
	if _, err := cached.Get(ctx, photo, "normal"); err == nil {
		t.Error("an out-of-date thumbnail was used")
	}

	for name, want := range map[string]Result{
		"broken.png": {Failed: true},
		"bomb.png":   {Failed: true},
		"icon.svg":   {Path: filepath.Join(files, "icon.svg")},
		"clip.mp4":   {},
	} {
		if res, err := s.Get(ctx, filepath.Join(files, name), "large"); err != nil || res != want {
			t.Errorf("%s: %+v %v, want %+v", name, res, err, want)
		}
	}
	// A failure is recorded and not tried again
	fail := filepath.Join(cache, "thumbnails", failDir, Hash(filesearch.FileURI(filepath.Join(files, "broken.png")))+".png")
	if _, err := os.Stat(fail); err != nil {
		t.Errorf("no fail record: %v", err)
	}
	if res, err := cached.Get(ctx, filepath.Join(files, "broken.png"), "normal"); err != nil || !res.Failed {
		t.Errorf("failed again: %+v %v", res, err)
	}
	if _, err := s.Get(ctx, photo, "huge"); err == nil {
		t.Error("an unknown size")
	}
}
