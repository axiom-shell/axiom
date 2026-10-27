package palette

import (
	"fmt"
	"math"
)

// A color in OKLab (L 0-1, a and b about ±0.4): a perceptual space, so
// equal lightness looks equally light at every hue.
type lab struct{ L, A, B float64 }

func (p lab) dist2(q lab) float64 {
	dl, da, db := p.L-q.L, p.A-q.A, p.B-q.B
	return dl*dl + da*da + db*db
}

// lch is the color as lightness, chroma and hue (degrees, 0-360).
func (p lab) lch() (l, c, h float64) {
	return p.L, math.Hypot(p.A, p.B), mod360(math.Atan2(p.B, p.A) * 180 / math.Pi)
}

// An sRGB color, 8 bits a channel.
type rgb8 [3]uint8

func (c rgb8) hex() string { return fmt.Sprintf("#%02x%02x%02x", c[0], c[1], c[2]) }

func (c rgb8) lab() lab {
	return toOKLab(float64(c[0])/255, float64(c[1])/255, float64(c[2])/255)
}

// luminance is WCAG's relative luminance.
func (c rgb8) luminance() float64 {
	return 0.2126*toLinear(float64(c[0])/255) + 0.7152*toLinear(float64(c[1])/255) + 0.0722*toLinear(float64(c[2])/255)
}

// contrast is the WCAG contrast ratio of two colors (1-21).
func contrast(a, b rgb8) float64 {
	la, lb := a.luminance(), b.luminance()
	if la < lb {
		la, lb = lb, la
	}
	return (la + 0.05) / (lb + 0.05)
}

func toLinear(c float64) float64 {
	if c <= 0.04045 {
		return c / 12.92
	}
	return math.Pow((c+0.055)/1.055, 2.4)
}

func fromLinear(c float64) float64 {
	if c <= 0.0031308 {
		return c * 12.92
	}
	return 1.055*math.Pow(c, 1/2.4) - 0.055
}

// toOKLab converts sRGB channels in 0-1 (Björn Ottosson's matrices).
func toOKLab(r, g, b float64) lab {
	r, g, b = toLinear(r), toLinear(g), toLinear(b)
	l := math.Cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
	m := math.Cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
	s := math.Cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
	return lab{
		0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
		1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
		0.0259040371*l + 0.7827717662*m - 0.8086757660*s,
	}
}

// srgb converts back, unclipped: a channel outside 0-1 is out of gamut.
func (p lab) srgb() [3]float64 {
	l := p.L + 0.3963377774*p.A + 0.2158037573*p.B
	m := p.L - 0.1055613458*p.A - 0.0638541728*p.B
	s := p.L - 0.0894841775*p.A - 1.2914855480*p.B
	l, m, s = l*l*l, m*m*m, s*s*s
	return [3]float64{
		fromLinear(4.0767416621*l - 3.3077115913*m + 0.2309699292*s),
		fromLinear(-1.2684380046*l + 2.6097574011*m - 0.3413193965*s),
		fromLinear(-0.0041960863*l - 0.7034186147*m + 1.7076147010*s),
	}
}

func inGamut(c [3]float64) bool {
	for _, v := range c {
		if v < -1e-4 || v > 1+1e-4 {
			return false
		}
	}
	return true
}

// clip rounds a color to 8 bits, clamping it into the gamut.
func clip(c [3]float64) rgb8 {
	var out rgb8
	for i, v := range c {
		out[i] = uint8(math.Round(min(max(v, 0), 1) * 255))
	}
	return out
}

func fromLCH(l, c, h float64) lab {
	rad := h * math.Pi / 180
	return lab{l, c * math.Cos(rad), c * math.Sin(rad)}
}

// lchColor is the OKLCH color in sRGB, its chroma reduced (keeping
// lightness and hue) until it fits.
func lchColor(l, c, h float64) rgb8 {
	if !inGamut(fromLCH(l, c, h).srgb()) {
		lo, hi := 0.0, c
		for range 24 {
			mid := (lo + hi) / 2
			if inGamut(fromLCH(l, mid, h).srgb()) {
				lo = mid
			} else {
				hi = mid
			}
		}
		c = lo
	}
	return clip(fromLCH(l, c, h).srgb())
}

func mod360(h float64) float64 {
	h = math.Mod(h, 360)
	if h < 0 {
		h += 360
	}
	return h
}

// hueDiff is the signed shortest rotation from hue a to hue b, in degrees.
func hueDiff(a, b float64) float64 {
	return mod360(b-a+180) - 180
}
