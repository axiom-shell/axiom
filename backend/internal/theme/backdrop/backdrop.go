// Package backdrop turns the wallpaper that is shown into a small grid of
// luminance levels, the shell's answer to "what is behind this bar or this
// module". Pure: no I/O; package theme reads the image. QML maps each
// surface's rectangle onto the grid (geometry is the shell's) and decides
// the ink, the fill and the shade with the style layer's maths. Each cell
// holds three grey levels (the sRGB grey whose WCAG luminance is the cell's):
// the mean, the darkest and the brightest of its sub-samples.
package backdrop

import (
	"image"
	"image/color"
	"math"

	"github.com/axiom-shell/axiom/backend/internal/theme/palette"
)

const (
	// longSide is the cells along the image's longer side
	longSide = 96
	// subs is the sub-samples a cell is split into, each way
	subs = 4
	// samples is the most source points a sub-sample averages, each way
	samples = 8
)

// Grid is the wallpaper as Cols×Rows cells, row by row, in the image's own
// coordinates (Width×Height pixels: QML places it with the wallpaper's own
// fill, whose rectangles are rounded).
type Grid struct {
	Cols   int    `json:"cols"`
	Rows   int    `json:"rows"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Mean   []byte `json:"mean"`
	Low    []byte `json:"low"`
	High   []byte `json:"high"`
}

// Sample is the grid of img: longSide cells on its longer side (the other
// by aspect, at least one), each cell subs×subs sub-samples, each the mean,
// in linear light, of up to samples×samples source points (alpha ignored,
// as for a wallpaper).
func Sample(img image.Image) Grid {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	g := Grid{Cols: 1, Rows: 1, Width: w, Height: h}
	if w <= 0 || h <= 0 {
		g.Mean, g.Low, g.High = []byte{0}, []byte{0}, []byte{0}
		return g
	}
	if w >= h {
		g.Cols, g.Rows = longSide, max(1, int(math.Round(float64(h)*longSide/float64(w))))
	} else {
		g.Cols, g.Rows = max(1, int(math.Round(float64(w)*longSide/float64(h)))), longSide
	}
	n := g.Cols * g.Rows
	g.Mean, g.Low, g.High = make([]byte, 0, n), make([]byte, 0, n), make([]byte, 0, n)
	for cy := range g.Rows {
		y0, y1 := cy*h/g.Rows, (cy+1)*h/g.Rows
		for cx := range g.Cols {
			x0, x1 := cx*w/g.Cols, (cx+1)*w/g.Cols
			var sum float64
			lo, hi := math.Inf(1), math.Inf(-1)
			for sy := range subs {
				ya, yb := part(y0, y1, sy)
				for sx := range subs {
					xa, xb := part(x0, x1, sx)
					l := mean(img, b.Min.X, b.Min.Y, xa, xb, ya, yb)
					sum += l
					lo, hi = min(lo, l), max(hi, l)
				}
			}
			g.Mean = append(g.Mean, palette.GreyOf(sum/(subs*subs)))
			g.Low = append(g.Low, palette.GreyOf(lo))
			g.High = append(g.High, palette.GreyOf(hi))
		}
	}
	return g
}

// part is the i-th of subs equal parts of [lo, hi), at least one pixel wide.
func part(lo, hi, i int) (int, int) {
	a := lo + i*(hi-lo)/subs
	return a, max(a+1, lo+(i+1)*(hi-lo)/subs)
}

// mean is the average luminance (linear light) of up to samples² source
// points spread evenly over [x0, x1)×[y0, y1) (palette's own pattern).
func mean(img image.Image, ox, oy, x0, x1, y0, y1 int) float64 {
	var sum float64
	count := 0
	xs := spread(x0, x1)
	for _, y := range spread(y0, y1) {
		for _, x := range xs {
			c := color.NRGBAModel.Convert(img.At(ox+x, oy+y)).(color.NRGBA)
			sum += palette.LinearOf(c.R, c.G, c.B)
			count++
		}
	}
	return sum / float64(count)
}

// spread is up to `samples` positions evenly over [lo, hi).
func spread(lo, hi int) []int {
	n := min(hi-lo, samples)
	out := make([]int, n)
	for i := range n {
		out[i] = lo + (2*i+1)*(hi-lo)/(2*n)
	}
	return out
}
