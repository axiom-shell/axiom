package nightlight

import "math"

// Neutral is the temperature that leaves a screen as it is.
const Neutral = 6500

// Whitepoint is how much of each channel a night light at kelvin keeps,
// times brightness (the Gamma setting, 0-1): 1, 1, 1 at 6500 K and full
// brightness. Tanner Helland's fit to blackbody colors (the one
// components/methods/ColorTemperature shows), relative to 6500 K's.
func Whitepoint(kelvin int, brightness float64) (r, g, b float64) {
	r, g, b = helland(float64(kelvin))
	nr, ng, nb := helland(Neutral)
	brightness = math.Max(0, math.Min(1, brightness))
	scale := func(v, n float64) float64 { return math.Min(1, v/n) * brightness }
	return scale(r, nr), scale(g, ng), scale(b, nb)
}

// helland is the color of light at kelvin (clamped to 1000-40000), each
// channel 0-255.
func helland(kelvin float64) (r, g, b float64) {
	t := math.Max(1000, math.Min(40000, kelvin)) / 100
	clamp := func(v float64) float64 { return math.Max(0, math.Min(255, v)) }
	if t <= 66 {
		r = 255
		g = 99.4708025861*math.Log(t) - 161.1195681661
	} else {
		r = 329.698727446 * math.Pow(t-60, -0.1332047592)
		g = 288.1221695283 * math.Pow(t-60, -0.0755148492)
	}
	switch {
	case t >= 66:
		b = 255
	case t <= 19:
		b = 0
	default:
		b = 138.5177312231*math.Log(t-10) - 305.0447927307
	}
	return clamp(r), clamp(g), clamp(b)
}

// Matrix is the color transform (row major, 3×3) scaling each channel.
func Matrix(r, g, b float64) [9]float64 {
	return [9]float64{r, 0, 0, 0, g, 0, 0, 0, b}
}

// Ramps are gamma ramps of size entries per channel for those scales:
// red's, then green's, then blue's, each linear from 0 to the channel's
// share of full (65535), as zwlr_gamma_control_v1 takes them.
func Ramps(size int, r, g, b float64) []uint16 {
	out := make([]uint16, 0, 3*size)
	for _, scale := range []float64{r, g, b} {
		for i := range size {
			v := 1.0
			if size > 1 {
				v = float64(i) / float64(size-1)
			}
			out = append(out, uint16(math.Round(v*scale*65535)))
		}
	}
	return out
}
