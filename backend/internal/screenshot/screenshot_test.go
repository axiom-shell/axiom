package screenshot

import (
	"errors"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// solid is a w×h picture of one colour
func solid(w, h int, c color.NRGBA) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.SetNRGBA(x, y, c)
		}
	}
	return img
}

var (
	red  = color.NRGBA{255, 0, 0, 255}
	blue = color.NRGBA{0, 0, 255, 255}
	none = color.NRGBA{}
)

func TestCompose(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		pieces []Placed
		area   Rect
		size   image.Point
		// pixel → the colour it must be
		at map[image.Point]color.NRGBA
	}{
		{
			name: "two monitors side by side at scale 1",
			pieces: []Placed{
				{solid(40, 30, red), Rect{1880, 100, 40, 30}},
				{solid(60, 30, blue), Rect{1920, 100, 60, 30}},
			},
			area: Rect{1880, 100, 100, 30},
			size: image.Pt(100, 30),
			at:   map[image.Point]color.NRGBA{{0, 0}: red, {39, 29}: red, {40, 0}: blue, {99, 29}: blue},
		},
		{
			name: "a scale-1 piece is scaled up to the scale-2 one beside it",
			pieces: []Placed{
				{solid(10, 20, red), Rect{0, 0, 10, 20}},
				{solid(20, 40, blue), Rect{10, 0, 10, 20}},
			},
			area: Rect{0, 0, 20, 20},
			size: image.Pt(40, 40),
			at:   map[image.Point]color.NRGBA{{0, 0}: red, {19, 39}: red, {20, 0}: blue, {39, 39}: blue},
		},
		{
			name: "fractional scales: the larger (1.5) wins",
			pieces: []Placed{
				{solid(30, 30, red), Rect{0, 0, 20, 20}},
				{solid(20, 20, blue), Rect{20, 0, 20, 20}},
			},
			area: Rect{0, 0, 40, 20},
			size: image.Pt(60, 30),
			at:   map[image.Point]color.NRGBA{{0, 0}: red, {29, 29}: red, {30, 0}: blue, {59, 29}: blue},
		},
		{
			name: "monitors at different heights leave a transparent gap",
			pieces: []Placed{
				{solid(10, 20, red), Rect{0, 0, 10, 20}},
				{solid(10, 10, blue), Rect{10, 10, 10, 10}},
			},
			area: Rect{0, 0, 20, 20},
			size: image.Pt(20, 20),
			at:   map[image.Point]color.NRGBA{{5, 5}: red, {15, 5}: none, {19, 9}: none, {15, 15}: blue},
		},
		{
			name: "monitors on top of each other, at negative positions",
			pieces: []Placed{
				{solid(10, 10, red), Rect{-10, -10, 10, 10}},
				{solid(10, 10, blue), Rect{-10, 0, 10, 10}},
			},
			area: Rect{-10, -10, 10, 20},
			size: image.Pt(10, 20),
			at:   map[image.Point]color.NRGBA{{0, 9}: red, {0, 10}: blue},
		},
		{
			name: "a piece past the area is clipped",
			pieces: []Placed{
				{solid(20, 10, red), Rect{0, 0, 20, 10}},
			},
			area: Rect{5, 0, 10, 10},
			size: image.Pt(10, 10),
			at:   map[image.Point]color.NRGBA{{0, 0}: red, {9, 9}: red},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			img, err := Compose(tt.pieces, tt.area)
			if err != nil {
				t.Fatal(err)
			}
			if got := img.Bounds().Size(); got != tt.size {
				t.Fatalf("size %v, want %v", got, tt.size)
			}
			for p, want := range tt.at {
				if got := img.NRGBAAt(p.X, p.Y); got != want {
					t.Errorf("at %v: %v, want %v", p, got, want)
				}
			}
		})
	}
}

func TestComposeRefuses(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		pieces []Placed
		area   Rect
	}{
		{"no pieces", nil, Rect{0, 0, 10, 10}},
		{"an empty area", []Placed{{solid(1, 1, red), Rect{0, 0, 1, 1}}}, Rect{0, 0, 0, 10}},
		{"an empty piece", []Placed{{solid(1, 1, red), Rect{0, 0, 0, 1}}}, Rect{0, 0, 1, 1}},
		{"too large", []Placed{{solid(4, 4, red), Rect{0, 0, 1, 1}}}, Rect{0, 0, 10000, 10}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Compose(tt.pieces, tt.area)
			var e *axerr.Error
			if !errors.As(err, &e) || e.Kind != axerr.BadRequest {
				t.Fatalf("err %v, want bad_request", err)
			}
		})
	}
}

func writePNG(t *testing.T, path string, img image.Image) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		t.Fatal(err)
	}
}

func TestStitch(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	a, b := filepath.Join(dir, "a.png"), filepath.Join(dir, "b.png")
	writePNG(t, a, solid(10, 10, red))
	writePNG(t, b, solid(20, 20, blue))
	out := filepath.Join(dir, "out.png")
	size, err := Stitch([]Piece{{a, Rect{0, 0, 10, 10}}, {b, Rect{10, 0, 10, 10}}}, Rect{0, 0, 20, 10}, out)
	if err != nil {
		t.Fatal(err)
	}
	if size != image.Pt(40, 20) {
		t.Fatalf("size %v", size)
	}
	f, err := os.Open(out)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	img, err := png.Decode(f)
	if err != nil {
		t.Fatal(err)
	}
	if img.Bounds().Size() != size {
		t.Fatalf("written %v, said %v", img.Bounds().Size(), size)
	}
	if got := color.NRGBAModel.Convert(img.At(39, 19)); got != blue {
		t.Errorf("bottom right %v, want blue", got)
	}
}

func TestStitchRefuses(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	notPNG := filepath.Join(dir, "x.png")
	os.WriteFile(notPNG, []byte("not a png"), 0o600)
	tests := []struct {
		name   string
		pieces []Piece
		out    string
		kind   axerr.Kind
	}{
		{"a relative output", []Piece{{notPNG, Rect{0, 0, 1, 1}}}, "out.png", axerr.BadRequest},
		{"a relative piece", []Piece{{"a.png", Rect{0, 0, 1, 1}}}, filepath.Join(dir, "o.png"), axerr.BadRequest},
		{"a missing piece", []Piece{{filepath.Join(dir, "gone.png"), Rect{0, 0, 1, 1}}}, filepath.Join(dir, "o.png"), axerr.NotFound},
		{"not a PNG", []Piece{{notPNG, Rect{0, 0, 1, 1}}}, filepath.Join(dir, "o.png"), axerr.BadRequest},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Stitch(tt.pieces, Rect{0, 0, 1, 1}, tt.out)
			var e *axerr.Error
			if !errors.As(err, &e) || e.Kind != tt.kind {
				t.Fatalf("err %v, want %s", err, tt.kind)
			}
		})
	}
}
