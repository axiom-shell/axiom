package palette

import (
	"image"
	"image/color"
	"math"
)

const (
	thumbnail  = 128 // the longer side analysed (Material quantizes ~128 px too)
	samples    = 8   // source samples per axis averaged into a thumbnail pixel
	candidates = 24  // clusters: enough that small vivid areas get their own
	binSize    = 0.02
	iterations = 24
)

// Analysis is what the palette needs to know about an image: its main
// colors and how its pixels spread over hue and chroma.
type Analysis struct {
	candidates []candidate
	// mean chroma over every pixel
	colorfulness float64
	// the image's overall cast: the chroma and hue of its mean a/b
	castChroma, castHue float64
}

type candidate struct {
	color   rgb8
	L, C, H float64
	// population: the share of pixels nearest it; hueShare: the share of
	// chromatic pixels within 15° of its hue (Material's "excited
	// proportion")
	population, hueShare float64
}

// Analyze reads an image's colors from a thumbnail of it.
func Analyze(img image.Image) *Analysis {
	pixels := downscale(img)
	a := &Analysis{}
	seen := map[rgb8]bool{}
	var labs []lab
	for _, c := range cluster(pixels, candidates) {
		rgb := clip(c.srgb())
		if seen[rgb] {
			continue
		}
		seen[rgb] = true
		p := rgb.lab()
		l, ch, h := p.lch()
		labs = append(labs, p)
		a.candidates = append(a.candidates, candidate{color: rgb, L: l, C: ch, H: h})
	}

	var meanA, meanB float64
	for _, p := range pixels {
		a.candidates[nearest(labs, p)].population++
		_, c, h := p.lch()
		a.colorfulness += c
		meanA += p.A
		meanB += p.B
		if c < minChroma {
			continue
		}
		for i := range a.candidates {
			if math.Abs(hueDiff(a.candidates[i].H, h)) <= 15 {
				a.candidates[i].hueShare++
			}
		}
	}
	n := float64(len(pixels))
	for i := range a.candidates {
		a.candidates[i].population /= n
		a.candidates[i].hueShare /= n
	}
	a.colorfulness /= n
	meanA, meanB = meanA/n, meanB/n
	a.castChroma = math.Hypot(meanA, meanB)
	a.castHue = mod360(math.Atan2(meanB, meanA) * 180 / math.Pi)
	return a
}

// downscale is the image fitted into a thumbnail, as OKLab pixels: each
// thumbnail pixel the mean of up to samples² source pixels spread over its
// area (alpha ignored, as for a wallpaper).
func downscale(img image.Image) []lab {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	tw, th := w, h
	if w > thumbnail || h > thumbnail {
		if w >= h {
			tw, th = thumbnail, max(1, int(math.Round(float64(h)*thumbnail/float64(w))))
		} else {
			tw, th = max(1, int(math.Round(float64(w)*thumbnail/float64(h)))), thumbnail
		}
	}
	out := make([]lab, 0, tw*th)
	for ty := range th {
		y0, y1 := ty*h/th, (ty+1)*h/th
		for tx := range tw {
			x0, x1 := tx*w/tw, (tx+1)*w/tw
			var sum [3]float64
			count := 0
			for _, y := range spread(y0, y1) {
				for _, x := range spread(x0, x1) {
					c := color.NRGBAModel.Convert(img.At(b.Min.X+x, b.Min.Y+y)).(color.NRGBA)
					sum[0] += float64(c.R)
					sum[1] += float64(c.G)
					sum[2] += float64(c.B)
					count++
				}
			}
			d := 255 * float64(count)
			out = append(out, toOKLab(sum[0]/d, sum[1]/d, sum[2]/d))
		}
	}
	return out
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

func nearest(centres []lab, p lab) int {
	best, bestD := 0, math.Inf(1)
	for i, c := range centres {
		if d := p.dist2(c); d < bestD {
			best, bestD = i, d
		}
	}
	return best
}

// cluster is weighted k-means over the pixels, binned in OKLab first so
// that noise and single stray pixels carry little weight. The starts are
// k-means++'s, deterministically: each the bin that the most pixels would
// gain by (weight × squared distance to the nearest start so far), so a
// small vivid area still gets a cluster of its own, and an image always
// gives the same colors.
func cluster(pixels []lab, k int) []lab {
	type bin struct {
		sum    lab
		weight float64
	}
	index := map[[3]int]int{}
	var bins []bin
	for _, p := range pixels {
		key := [3]int{int(math.Round(p.L / binSize)), int(math.Round(p.A / binSize)), int(math.Round(p.B / binSize))}
		i, ok := index[key]
		if !ok {
			i = len(bins)
			index[key] = i
			bins = append(bins, bin{})
		}
		bins[i].sum = lab{bins[i].sum.L + p.L, bins[i].sum.A + p.A, bins[i].sum.B + p.B}
		bins[i].weight++
	}
	colors := make([]lab, len(bins))
	for i, b := range bins {
		colors[i] = lab{b.sum.L / b.weight, b.sum.A / b.weight, b.sum.B / b.weight}
	}

	heaviest := 0
	for i, b := range bins {
		if b.weight > bins[heaviest].weight {
			heaviest = i
		}
	}
	centres := []lab{colors[heaviest]}
	gain := make([]float64, len(bins))
	for i := range bins {
		gain[i] = colors[i].dist2(centres[0])
	}
	for len(centres) < min(k, len(bins)) {
		best, bestGain := -1, 0.0
		for i, b := range bins {
			if g := b.weight * gain[i]; g > bestGain {
				best, bestGain = i, g
			}
		}
		if best < 0 {
			break
		}
		centres = append(centres, colors[best])
		for i := range bins {
			gain[i] = min(gain[i], colors[i].dist2(colors[best]))
		}
	}

	for range iterations {
		sums := make([]bin, len(centres))
		for i, c := range colors {
			j := nearest(centres, c)
			w := bins[i].weight
			sums[j].sum = lab{sums[j].sum.L + c.L*w, sums[j].sum.A + c.A*w, sums[j].sum.B + c.B*w}
			sums[j].weight += w
		}
		moved := 0.0
		for j, s := range sums {
			if s.weight == 0 {
				continue
			}
			m := lab{s.sum.L / s.weight, s.sum.A / s.weight, s.sum.B / s.weight}
			moved = max(moved, m.dist2(centres[j]))
			centres[j] = m
		}
		if moved < 1e-10 {
			break
		}
	}
	return centres
}
