package screenshot

import (
	"errors"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"golang.org/x/image/bmp"

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

// stripes is a w×h picture of one-pixel columns, red then blue
func stripes(w, h int) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.SetNRGBA(x, y, []color.NRGBA{red, blue}[x%2])
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

func writeBMP(t *testing.T, path string, img image.Image) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := bmp.Encode(f, img); err != nil {
		t.Fatal(err)
	}
}

// readPNG is the picture in the PNG at path
func readPNG(t *testing.T, path string) image.Image {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	img, err := png.Decode(f)
	if err != nil {
		t.Fatal(err)
	}
	return img
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
	img := readPNG(t, out)
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

// A piece a pixel off its place at the same scale is never resampled: no
// pixel mixes red and blue
func TestComposeSameScaleSharp(t *testing.T) {
	t.Parallel()
	img, err := Compose([]Placed{
		{solid(752, 3, red), Rect{0, 0, 501, 2}},
		{stripes(753, 3), Rect{501, 0, 502, 2}},
	}, Rect{0, 0, 1003, 2})
	if err != nil {
		t.Fatal(err)
	}
	b := img.Bounds()
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if c := img.NRGBAAt(x, y); c != red && c != blue {
				t.Fatalf("at (%d, %d): %v, a blend", x, y, c)
			}
		}
	}
}

// testdata/qt-grab.bmp and .png are one grab of the same item, saved by Qt
// both ways: a scratch tst_grab.qml (not committed) run with
// QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tst_grab.qml
// (add QT_QUICK_BACKEND=software if the offscreen grab fails or comes back
// empty). Its root is an opaque 64x48 Rectangle (a gradient of opaque
// stops) with a Text on top; grabToImage, then saveToFile to each name.
// A one-screen shot saved through the BMP piece is the PNG Qt would have
// written, pixel for pixel
func TestStitchQtParity(t *testing.T) {
	t.Parallel()
	want := readPNG(t, filepath.Join("testdata", "qt-grab.png"))
	b := want.Bounds()
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if _, _, _, a := want.At(x, y).RGBA(); a != 0xffff {
				t.Fatalf("fixture pixel (%d, %d) is not opaque", x, y)
			}
		}
	}
	bmpPath, err := filepath.Abs(filepath.Join("testdata", "qt-grab.bmp"))
	if err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "out.png")
	area := Rect{0, 0, 64, 48}
	size, err := Stitch([]Piece{{bmpPath, area}}, area, out)
	if err != nil {
		t.Fatal(err)
	}
	got := readPNG(t, out)
	if got.Bounds() != b || size != b.Size() {
		t.Fatalf("size %v (said %v), want %v", got.Bounds(), size, b)
	}
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if g, w := color.NRGBAModel.Convert(got.At(x, y)), color.NRGBAModel.Convert(want.At(x, y)); g != w {
				t.Fatalf("at (%d, %d): %v, want %v", x, y, g, w)
			}
		}
	}
}

// One piece that is the whole area is written as it is (Compose would
// size it by the scale of its rect), and its refusals are Compose's
func TestStitchOnePiece(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	tall, wide := filepath.Join(dir, "tall.png"), filepath.Join(dir, "wide.png")
	writePNG(t, tall, solid(2, 1500, red))
	writePNG(t, wide, solid(2, 40000, red))
	out := filepath.Join(dir, "out.png")
	area := Rect{0, 0, 1, 1000}
	size, err := Stitch([]Piece{{tall, area}}, area, out)
	if err != nil {
		t.Fatal(err)
	}
	if got := readPNG(t, out).Bounds().Size(); got != image.Pt(2, 1500) || size != got {
		t.Fatalf("written %v, said %v, want 2x1500", got, size)
	}
	tests := []struct {
		name  string
		piece string
		area  Rect
	}{
		{"an empty area", tall, Rect{}},
		{"too large", wide, Rect{0, 0, 1, 1}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			_, err := Stitch([]Piece{{tt.piece, tt.area}}, tt.area, filepath.Join(dir, "o-"+tt.name+".png"))
			var e *axerr.Error
			if !errors.As(err, &e) || e.Kind != axerr.BadRequest {
				t.Fatalf("err %v, want bad_request", err)
			}
		})
	}
}

// A BMP piece and a PNG piece stitch together as two PNGs do
func TestStitchBMP(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	a, b := filepath.Join(dir, "a.bmp"), filepath.Join(dir, "b.png")
	writeBMP(t, a, solid(10, 10, red))
	writePNG(t, b, solid(20, 20, blue))
	out := filepath.Join(dir, "out.png")
	size, err := Stitch([]Piece{{a, Rect{0, 0, 10, 10}}, {b, Rect{10, 0, 10, 10}}}, Rect{0, 0, 20, 10}, out)
	if err != nil {
		t.Fatal(err)
	}
	img := readPNG(t, out)
	if size != image.Pt(40, 20) || img.Bounds().Size() != size {
		t.Fatalf("written %v, said %v", img.Bounds().Size(), size)
	}
	if got := color.NRGBAModel.Convert(img.At(0, 0)); got != red {
		t.Errorf("top left %v, want red", got)
	}
	if got := color.NRGBAModel.Convert(img.At(39, 19)); got != blue {
		t.Errorf("bottom right %v, want blue", got)
	}
}
