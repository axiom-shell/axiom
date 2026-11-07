// Package screenshot stitches the screenshot picker's pieces into one
// picture (screenshot.stitch): a region dragged, or a window picked, across
// monitors is cropped by each monitor's picker from its own frozen frame,
// at that monitor's scale; this lays them out by their global logical
// position, at the largest scale among them (lower-scale pieces are scaled
// up), and writes the PNG. What no piece covers (a gap between monitors
// of different sizes or offsets) stays transparent.
package screenshot

import (
	"bytes"
	"image"
	"image/png"
	"math"
	"os"
	"path/filepath"

	"golang.org/x/image/draw"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// maxSide caps the stitched picture's width and height in pixels: far
// past any real desktop, short of an allocation a bad request could make
// fail the daemon.
const maxSide = 32768

// Rect is an area in global logical pixels (the compositor's layout).
type Rect struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// Piece is one monitor's part of the picture: the PNG at Path, which
// shows Rect.
type Piece struct {
	Path string `json:"path"`
	Rect
}

// Placed is a decoded piece and the area it shows.
type Placed struct {
	Image image.Image
	Rect  Rect
}

// Compose lays pieces out over area at the largest scale among them
// (a piece's pixels per logical pixel, by its width), each scaled to its
// place where its own scale is lower; what none covers is transparent. A
// piece is clipped to area.
func Compose(pieces []Placed, area Rect) (*image.NRGBA, error) {
	if len(pieces) == 0 {
		return nil, axerr.New(axerr.BadRequest, "screenshot.stitch: no pieces")
	}
	if !(area.Width > 0 && area.Height > 0) {
		return nil, axerr.New(axerr.BadRequest, "screenshot.stitch: an empty area")
	}
	scale := 0.0
	for _, p := range pieces {
		b := p.Image.Bounds()
		if !(p.Rect.Width > 0 && p.Rect.Height > 0) || b.Empty() {
			return nil, axerr.New(axerr.BadRequest, "screenshot.stitch: an empty piece")
		}
		scale = math.Max(scale, math.Max(float64(b.Dx())/p.Rect.Width, float64(b.Dy())/p.Rect.Height))
	}
	w, h := int(math.Round(area.Width*scale)), int(math.Round(area.Height*scale))
	if w < 1 || h < 1 || w > maxSide || h > maxSide {
		return nil, axerr.New(axerr.BadRequest, "screenshot.stitch: a %dx%d picture", w, h)
	}
	out := image.NewNRGBA(image.Rect(0, 0, w, h))
	at := func(v float64) int { return int(math.Round(v * scale)) }
	for _, p := range pieces {
		dr := image.Rect(at(p.Rect.X-area.X), at(p.Rect.Y-area.Y), at(p.Rect.X+p.Rect.Width-area.X), at(p.Rect.Y+p.Rect.Height-area.Y))
		src := p.Image.Bounds()
		if dr.Dx() == src.Dx() && dr.Dy() == src.Dy() {
			// Already at this scale: copied pixel for pixel (clipped to out)
			draw.Draw(out, dr, p.Image, src.Min, draw.Src)
			continue
		}
		// A piece at this scale but a pixel off its place's size (each
		// picker rounds its own crop): stretched by repeating a row or
		// column, not resampled, so it stays sharp. Scale clips to out's
		// bounds itself
		var interp draw.Interpolator = draw.CatmullRom
		if abs(dr.Dx()-src.Dx()) <= 1 && abs(dr.Dy()-src.Dy()) <= 1 {
			interp = draw.NearestNeighbor
		}
		interp.Scale(out, dr, p.Image, src, draw.Src, nil)
	}
	return out, nil
}

// Stitch decodes pieces, composes them over area (Compose) and writes the
// PNG to out (an absolute path, replaced atomically); returns the
// picture's size in pixels.
func Stitch(pieces []Piece, area Rect, out string) (image.Point, error) {
	if !filepath.IsAbs(out) {
		return image.Point{}, axerr.New(axerr.BadRequest, "screenshot.stitch: %q is not an absolute path", out)
	}
	placed := make([]Placed, 0, len(pieces))
	for _, p := range pieces {
		img, err := decode(p.Path)
		if err != nil {
			return image.Point{}, err
		}
		placed = append(placed, Placed{Image: img, Rect: p.Rect})
	}
	img, err := Compose(placed, area)
	if err != nil {
		return image.Point{}, err
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return image.Point{}, axerr.Wrap(axerr.Internal, err, "screenshot.stitch")
	}
	if err := fsx.WriteFile(out, buf.Bytes(), 0o644); err != nil {
		return image.Point{}, err
	}
	return img.Bounds().Size(), nil
}

func abs(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func decode(path string) (image.Image, error) {
	if !filepath.IsAbs(path) {
		return nil, axerr.New(axerr.BadRequest, "screenshot.stitch: %q is not an absolute path", path)
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, axerr.Wrap(axerr.NotFound, err, "screenshot.stitch")
	}
	defer f.Close()
	img, err := png.Decode(f)
	if err != nil {
		return nil, axerr.Wrap(axerr.BadRequest, err, "screenshot.stitch: %s", path)
	}
	return img, nil
}
