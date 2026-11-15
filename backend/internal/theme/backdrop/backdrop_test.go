package backdrop

import (
	"image"
	"image/color"
	"testing"
)

func fill(w, h int, f func(x, y int) uint8) *image.NRGBA {
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			v := f(x, y)
			img.SetNRGBA(x, y, color.NRGBA{v, v, v, 255})
		}
	}
	return img
}

func near(a, b byte, tol int) bool {
	d := int(a) - int(b)
	return d >= -tol && d <= tol
}

func TestSolids(t *testing.T) {
	for _, v := range []uint8{0, 128, 255} {
		g := Sample(fill(400, 200, func(int, int) uint8 { return v }))
		if g.Cols != 96 || g.Rows != 48 || g.Width != 400 || g.Height != 200 {
			t.Fatalf("%d: grid %dx%d of %dx%d", v, g.Cols, g.Rows, g.Width, g.Height)
		}
		for i := range g.Mean {
			if !near(g.Mean[i], v, 1) || !near(g.Low[i], v, 1) || !near(g.High[i], v, 1) {
				t.Fatalf("%d: cell %d is %d/%d/%d", v, i, g.Low[i], g.Mean[i], g.High[i])
			}
		}
	}
}

func TestHalves(t *testing.T) {
	g := Sample(fill(960, 480, func(x, _ int) uint8 {
		if x < 480 {
			return 0
		}
		return 255
	}))
	for y := range g.Rows {
		for x := range g.Cols {
			i := y*g.Cols + x
			want := byte(0)
			if x >= g.Cols/2 {
				want = 255
			}
			if g.Mean[i] != want || g.Low[i] != want || g.High[i] != want {
				t.Fatalf("cell %d,%d is %d, want %d", x, y, g.Mean[i], want)
			}
		}
	}
}

func TestChecker(t *testing.T) {
	// 16 px cells: two 8 px squares each way, sub-samples of 4 px inside one
	g := Sample(fill(1536, 1536, func(x, y int) uint8 {
		if (x/8+y/8)%2 == 0 {
			return 0
		}
		return 255
	}))
	if g.Cols != 96 || g.Rows != 96 {
		t.Fatalf("grid %dx%d", g.Cols, g.Rows)
	}
	for i := range g.Mean {
		if g.Low[i] > 5 || g.High[i] < 250 || !near(g.Mean[i], 188, 6) {
			t.Fatalf("cell %d is %d/%d/%d", i, g.Low[i], g.Mean[i], g.High[i])
		}
	}
}

func TestGradient(t *testing.T) {
	g := Sample(fill(480, 480, func(_, y int) uint8 { return uint8(y * 255 / 479) }))
	for y := 1; y < g.Rows; y++ {
		if g.Mean[y*g.Cols] < g.Mean[(y-1)*g.Cols] {
			t.Fatalf("row %d (%d) is darker than the row above (%d)", y, g.Mean[y*g.Cols], g.Mean[(y-1)*g.Cols])
		}
	}
	if g.Mean[0] >= g.Mean[(g.Rows-1)*g.Cols] {
		t.Fatal("the gradient doesn't rise")
	}
}

func TestStrip(t *testing.T) {
	g := Sample(fill(1, 4000, func(_, y int) uint8 { return uint8(y % 256) }))
	if g.Cols != 1 || g.Rows != 96 || len(g.Mean) != 96 {
		t.Fatalf("grid %dx%d with %d cells", g.Cols, g.Rows, len(g.Mean))
	}
	wide := Sample(fill(4000, 1, func(int, int) uint8 { return 255 }))
	if wide.Rows != 1 || wide.Cols != 96 {
		t.Fatalf("grid %dx%d", wide.Cols, wide.Rows)
	}
	tiny := Sample(fill(2, 2, func(int, int) uint8 { return 255 }))
	if len(tiny.Mean) != tiny.Cols*tiny.Rows || tiny.Mean[0] != 255 {
		t.Fatalf("tiny: %+v", tiny)
	}
}
