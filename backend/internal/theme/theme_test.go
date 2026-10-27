package theme

import (
	"bytes"
	"encoding/binary"
	"errors"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/image/bmp"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

func writeImage(t *testing.T, path string, encode func(*bytes.Buffer, image.Image) error) {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 40, 20))
	for x := range 40 {
		for y := range 20 {
			img.Set(x, y, color.RGBA{uint8(x * 6), 80, uint8(200 - x*4), 255})
		}
	}
	var b bytes.Buffer
	if err := encode(&b, img); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, b.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestGenerate(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		encode func(*bytes.Buffer, image.Image) error
	}{
		{"wall.png", func(b *bytes.Buffer, img image.Image) error { return png.Encode(b, img) }},
		{"wall.bmp", func(b *bytes.Buffer, img image.Image) error { return bmp.Encode(b, img) }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			wall := filepath.Join(dir, tc.name)
			writeImage(t, wall, tc.encode)
			// A link to the image is recorded as the image itself
			link := filepath.Join(dir, "link")
			if err := os.Symlink(wall, link); err != nil {
				t.Fatal(err)
			}
			out := filepath.Join(dir, "themes") // made when missing
			files, err := Generate(link, out, time.Now())
			if err != nil {
				t.Fatal(err)
			}
			if len(files) != 10 || files[0] != filepath.Join(out, "wallpaper-tonal-dark.json") {
				t.Fatalf("files = %v", files)
			}
			raw, err := os.ReadFile(files[0])
			if err != nil {
				t.Fatal(err)
			}
			v, err := jsonx.Unmarshal(raw)
			if err != nil {
				t.Fatal(err)
			}
			generated := v.(*jsonx.Object).Value("generated").(*jsonx.Object)
			if got := generated.Value("wallpaper"); got != wall {
				t.Errorf("wallpaper = %v, want %s", got, wall)
			}
		})
	}
}

// A triple-screen panorama, wider than 8192 px, is well under the limit
func TestGeneratePanorama(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	wall := filepath.Join(dir, "panorama.png")
	img := image.NewGray(image.Rect(0, 0, 11520, 2160))
	var b bytes.Buffer
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(wall, b.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	if files, err := Generate(wall, filepath.Join(dir, "themes"), time.Now()); err != nil || len(files) != 10 {
		t.Fatalf("files = %v, err = %v", files, err)
	}
}

func TestGenerateRefuses(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	text := filepath.Join(dir, "notes.png")
	if err := os.WriteFile(text, []byte("not an image"), 0o644); err != nil {
		t.Fatal(err)
	}
	// A BMP whose header claims 10000×10000 pixels (100 MP): refused unread
	huge := filepath.Join(dir, "huge.bmp")
	var b bytes.Buffer
	if err := bmp.Encode(&b, image.NewRGBA(image.Rect(0, 0, 1, 1))); err != nil {
		t.Fatal(err)
	}
	header := b.Bytes()
	binary.LittleEndian.PutUint32(header[18:], 10000)
	binary.LittleEndian.PutUint32(header[22:], 10000)
	if err := os.WriteFile(huge, header, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		path string
		kind axerr.Kind
	}{
		{filepath.Join(dir, "missing.png"), axerr.NotFound},
		{text, axerr.BadRequest},
		{huge, axerr.BadRequest},
	} {
		_, err := Generate(tc.path, filepath.Join(dir, "themes"), time.Now())
		var e *axerr.Error
		if !errors.As(err, &e) || e.Kind != tc.kind {
			t.Errorf("%s: err = %v, want %s", tc.path, err, tc.kind)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "themes")); !os.IsNotExist(err) {
		t.Errorf("a refused image made the folder: %v", err)
	}
}
