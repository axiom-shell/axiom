// Package palette makes axiom's generated themes from a wallpaper: a
// dark/light base16 pair per style, as the theme files ThemeManager reads.
// Pure: no I/O; package theme reads the image and writes the files.
//
// Candidate colors come from k-means over the image in OKLab. The palette
// is built in OKLCH, Material-style:
//
//   - Seed: each candidate is weighed by how much of the image shares its
//     hue and by its chroma (Material's scoring), and the best one becomes
//     the primary accent (base0F, which the theme's `accent` points at).
//   - Neutrals (base00-base07): a fixed lightness ramp, tinted with the
//     image's overall color cast.
//   - Accents (base08-base0E): each slot keeps its meaning (red stays red
//     for errors) but takes its hue from a wallpaper color near it, or else
//     is rotated slightly toward the seed (Material's harmonize). Lightness
//     and chroma come from fixed per-hue targets, scaled by how colorful
//     the image is.
//
// A Style scales those steps, as Material's scheme variants do. The targets
// are measured from the hand-made themes in config/themes (Catppuccin,
// Tokyo Night, Gruvbox, Solarized), so generated themes sit in their range.
package palette

import (
	"cmp"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// Style is one way of building the pair. Every factor is 1 for tonal.
type Style struct {
	Name string
	// accent chroma, base0F's chroma range, how strongly the neutrals are
	// tinted
	Chroma, PrimaryChroma, Tint float64
	// tint the neutrals with the seed's hue, not the image's cast
	TintSeed bool
	// how far from its canonical hue a slot takes a wallpaper hue, and how
	// far a slot with none turns toward the seed (both stay within the
	// slot's cell, so red never turns orange)
	Deviation, Harmonize float64
	// 0-1: how far an accent's chroma moves to its wallpaper color's
	Fidelity float64
	// which distinct wallpaper hue is the seed (0: the best)
	SeedRank int
}

// Styles are every style, in the order they're generated.
var Styles = []Style{
	// Material's default: the wallpaper's main hue, calm accents
	{Name: "tonal", Chroma: 1, PrimaryChroma: 1, Tint: 1, Deviation: 1, Harmonize: 1},
	// Stronger color everywhere, with neutrals in the seed's hue
	{Name: "vibrant", Chroma: 1.35, PrimaryChroma: 1.3, Tint: 2, TintSeed: true, Deviation: 1, Harmonize: 1},
	// Accents as the wallpaper has them: any of its hues in the slot's
	// cell, at the chroma it has them in
	{Name: "faithful", Chroma: 1, PrimaryChroma: 1, Tint: 1, Deviation: 3, Harmonize: 2, Fidelity: 0.7},
	// Soft accents on nearly grey neutrals
	{Name: "muted", Chroma: 0.55, PrimaryChroma: 0.6, Tint: 0.45, Deviation: 1, Harmonize: 1},
	// The wallpaper's second hue as the seed (the tonal pair's accentAlt)
	{Name: "alternate", Chroma: 1, PrimaryChroma: 1, Tint: 1, Deviation: 1, Harmonize: 1, SeedRank: 1},
}

// Palette targets, OKLCH (L 0-1, C ~0-0.37, H degrees). Variant 0 is dark,
// 1 light.
var (
	// The neutral ramp's lightness, base00 → base07 (light runs light → dark)
	neutralL = [2][8]float64{
		{0.235, 0.305, 0.385, 0.48, 0.745, 0.86, 0.91, 0.965},
		{0.965, 0.93, 0.865, 0.80, 0.62, 0.44, 0.34, 0.25},
	}
	// How much of the neutral tint each ramp step carries (text is less tinted)
	neutralTint = [8]float64{0.9, 1.0, 1.05, 1.1, 0.85, 0.75, 0.5, 0.3}
	// base08-base0E, in order
	accents = []accent{
		{20, 14, [2][2]float64{{0.735, 0.145}, {0.535, 0.175}}, 0},  // red: error
		{50, 12, [2][2]float64{{0.80, 0.125}, {0.61, 0.150}}, 0},    // orange
		{82, 14, [2][2]float64{{0.855, 0.105}, {0.70, 0.140}}, -10}, // yellow: warning
		{135, 25, [2][2]float64{{0.825, 0.125}, {0.61, 0.140}}, 0},  // green: success
		{195, 30, [2][2]float64{{0.835, 0.095}, {0.58, 0.100}}, 0},  // cyan: info
		{255, 25, [2][2]float64{{0.745, 0.125}, {0.53, 0.160}}, 0},  // blue
		{315, 30, [2][2]float64{{0.77, 0.125}, {0.54, 0.160}}, 0},   // magenta
	}
	primaryL = [2]float64{0.80, 0.50}
	// clamp range for the seed's chroma
	primaryC = [2][2]float64{{0.09, 0.16}, {0.11, 0.19}}
	variants = [2]string{"dark", "light"}
)

type accent struct {
	hue, deviation float64
	target         [2][2]float64 // L, C per variant
	// added in light themes: dark yellows read olive, so light ones lean
	// amber (as Latte and Gruvbox Light do)
	lightShift float64
}

const (
	firstAccent     = 8     // base08: accents[i] is base08+i
	primary         = 15    // base0F, the seed's slot
	lightTint       = 0.7   // tint shows more on a light background
	minChroma       = 0.035 // below this a color counts as grey
	seedMinChroma   = 0.05  // Material's cutoff (15 CAM16 chroma) for a seed
	harmonizeMax    = 15.0  // Material's cap on rotating a hue toward the seed
	referenceChroma = 0.06  // image colorfulness the accent chroma targets assume
)

// slotName is base16 slot i's key, base00-base0F.
func slotName(i int) string { return fmt.Sprintf("base%02X", i) }

// seeds are candidate indices, best first by Material's score (chroma
// rescaled from CAM16 to OKLCH units), each at least 15° from the ones
// before.
func (a *Analysis) seeds() []int {
	var order []int
	score := make([]float64, len(a.candidates))
	for i, c := range a.candidates {
		if c.C < seedMinChroma || c.hueShare < 0.01 {
			continue
		}
		cam := c.C * 400
		factor := 0.3
		if cam < 48 {
			factor = 0.1
		}
		score[i] = c.hueShare*70 + (cam-48)*factor
		order = append(order, i)
	}
	slices.SortStableFunc(order, func(i, j int) int { return cmp.Compare(score[j], score[i]) })
	var picked []int
	for _, i := range order {
		if a.farFrom(i, picked, 15) {
			picked = append(picked, i)
		}
	}
	return picked
}

func (a *Analysis) farFrom(i int, others []int, degrees float64) bool {
	for _, j := range others {
		if math.Abs(hueDiff(a.candidates[i].H, a.candidates[j].H)) < degrees {
			return false
		}
	}
	return true
}

type hue struct {
	h, c    float64
	hasWall bool // the hue is a wallpaper color's (and c its chroma)
}

// pair is a style's two variants' colors, base00-base0F, the slot
// accentAlt points at and the seed (nil without one).
type pair struct {
	colors  [2][16]rgb8
	altSlot int
	seed    *rgb8
}

func (a *Analysis) build(s Style) pair {
	// The wallpaper's hues at least 40° apart, best first
	var distinct []int
	for _, i := range a.seeds() {
		if a.farFrom(i, distinct, 40) {
			distinct = append(distinct, i)
		}
	}
	var p pair
	var seedH, seedC float64
	switch {
	case s.SeedRank < len(distinct):
		c := a.candidates[distinct[s.SeedRank]]
		seedH, seedC, p.seed = c.H, c.C, &c.color
	case len(distinct) > 0:
		// Not that many hues: Material's tertiary, 60° on from the best
		seedH, seedC = mod360(a.candidates[distinct[0]].H+60), a.candidates[distinct[0]].C
	default:
		// A grey image: the cast's hue, with barely any color
		seedH, seedC = a.castHue, minChroma
	}

	// Another distinct wallpaper hue for accentAlt, else Material's tertiary
	altH := mod360(seedH + 60)
	for _, i := range distinct {
		if math.Abs(hueDiff(seedH, a.candidates[i].H)) >= 40 {
			altH = a.candidates[i].H
			break
		}
	}

	// Accent chroma follows how colorful the image is, within reason
	vivid := min(max(math.Sqrt(a.colorfulness/referenceChroma), 0.7), 1.15)
	if len(distinct) == 0 {
		vivid = 0.7
	}
	vivid *= s.Chroma

	// The neutrals take the image's cast, or the seed's hue when it has none
	neutralH := a.castHue
	if s.TintSeed || a.castChroma < 0.008 {
		neutralH = seedH
	}
	tint := min(max(0.008+a.castChroma*0.5+seedC*0.06, 0.008), 0.034) * s.Tint

	hues := make([]hue, len(accents))
	for i := range accents {
		hues[i] = a.accentHue(i, seedH, s)
	}
	// accentAlt is the slot nearest altH but red, which would read as an error
	closest := math.Inf(1)
	for i := 1; i < len(accents); i++ {
		if d := math.Abs(hueDiff(hues[i].h, altH)); d < closest {
			closest, p.altSlot = d, firstAccent+i
		}
	}

	for v := range variants {
		colors := &p.colors[v]
		t := tint
		if v == 1 {
			t *= lightTint
		}
		for i, l := range neutralL[v] {
			colors[i] = lchColor(l, t*neutralTint[i], neutralH)
		}
		bg := colors[0]
		for i, acc := range accents {
			l, c := acc.target[v][0], acc.target[v][1]*vivid
			h := hues[i].h
			if v == 1 {
				h += acc.lightShift
			}
			if hues[i].hasWall {
				c += (hues[i].c - c) * s.Fidelity
			}
			colors[firstAccent+i] = readable(l, c, h, bg, v)
		}
		lo, hi := primaryC[v][0]*s.PrimaryChroma, primaryC[v][1]*s.PrimaryChroma
		colors[primary] = readable(primaryL[v], min(max(seedC, lo), hi), seedH, bg, v)
	}
	return p
}

// accentHue is the hue for accent slot i: the wallpaper color near the
// slot's hue with the most weight, if there is one, else the slot's own
// hue rotated toward the seed (Material's harmonize).
func (a *Analysis) accentHue(i int, seedH float64, s Style) hue {
	acc := accents[i]
	// A slot's cell reaches halfway to its neighbours' hues
	cell := math.Inf(1)
	for j, other := range accents {
		if j != i {
			cell = min(cell, math.Abs(hueDiff(acc.hue, other.hue))/2)
		}
	}
	deviation := min(acc.deviation*s.Deviation, cell)
	// The weighted mean of those colors: a slight change to the image moves
	// it slightly, where picking one of them would jump between them
	var sum, x, y, c float64
	for _, cand := range a.candidates {
		if cand.C < minChroma*1.5 || math.Abs(hueDiff(acc.hue, cand.H)) > deviation {
			continue
		}
		w := cand.population * cand.C
		offset := hueDiff(acc.hue, cand.H) * math.Pi / 180
		sum, x, y, c = sum+w, x+w*math.Cos(offset), y+w*math.Sin(offset), c+w*cand.C
	}
	if sum > 0 {
		return hue{mod360(acc.hue + math.Atan2(y, x)*180/math.Pi), c / sum, true}
	}
	shift := hueDiff(acc.hue, seedH)
	rotation := math.Copysign(min(math.Abs(shift)*0.5, harmonizeMax*s.Harmonize, deviation), shift)
	return hue{h: mod360(acc.hue + rotation)}
}

// readable is the color with its lightness pushed away from the
// background until it has 3:1 contrast (WCAG) against it.
func readable(l, c, h float64, bg rgb8, variant int) rgb8 {
	step := 0.02
	if variant == 1 {
		step = -0.02
	}
	return pushed(l, c, h, bg, 3, step)
}

// pushed is the OKLCH color, its lightness moved by step until it has
// min contrast against bg (chroma shrinking to stay in sRGB).
func pushed(l, c, h float64, bg rgb8, min, step float64) rgb8 {
	color := lchColor(l, c, h)
	for contrast(color, bg) < min && (step < 0 && l > 0.05 || step > 0 && l < 0.98) {
		l += step
		color = lchColor(l, c, h)
	}
	return color
}

// Readable is fg ("#rrggbb") with at least min contrast against bg: its
// hue kept, its lightness moved away from the background only as far as
// needed, so a color that passes comes back unchanged. Anything that
// isn't two 6-digit hex colors comes back as it is.
func Readable(fg, bg string, min float64) string {
	f, okF := parseHex(fg)
	b, okB := parseHex(bg)
	if !okF || !okB || contrast(f, b) >= min {
		return fg
	}
	step := 0.01
	if contrast(b, rgb8{}) >= contrast(b, rgb8{255, 255, 255}) {
		step = -0.01 // a light background: darker
	}
	l, c, h := f.lab().lch()
	return pushed(l, c, h, b, min, step).hex()
}

// parseHex reads "#rrggbb".
func parseHex(s string) (rgb8, bool) {
	var c rgb8
	if len(s) != 7 || s[0] != '#' {
		return c, false
	}
	for i := range c {
		v, err := strconv.ParseUint(s[1+2*i:3+2*i], 16, 8)
		if err != nil {
			return c, false
		}
		c[i] = uint8(v)
	}
	return c, true
}

// File is one theme file: its name in the generated themes' folder and
// its bytes.
type File struct {
	Name string
	Data []byte
}

// Themes are every style's pair as theme files (wallpaper-<style>-dark|
// light.json): `semantic` is theme-defaults.json's dark map, `wallpaper`
// the image's absolute path, recorded with `at` in each file.
func Themes(a *Analysis, semantic *jsonx.Object, wallpaper string, at time.Time) []File {
	var files []File
	for _, s := range Styles {
		p := a.build(s)
		var seed any
		if p.seed != nil {
			seed = p.seed.hex()
		}
		generated := jsonx.Obj("source", "wallpaper", "style", s.Name, "wallpaper", wallpaper, "seed", seed,
			"timestamp", at.UTC().Format("2006-01-02T15:04:05.000000Z"))
		sem := jsonx.NewObject()
		for _, k := range semantic.Keys() {
			sem.Set(k, semantic.Value(k))
		}
		sem.Set("accent", slotName(primary))
		sem.Set("borderFocus", slotName(primary))
		sem.Set("accentAlt", slotName(p.altSlot))
		names := [2]string{"wallpaper-" + s.Name + "-dark", "wallpaper-" + s.Name + "-light"}
		for v, variant := range variants {
			colors := jsonx.NewObject()
			for i, c := range p.colors[v] {
				colors.Set(slotName(i), c.hex())
			}
			theme := jsonx.Obj("name", "Wallpaper "+title(s.Name)+" "+title(variant), "author", "axiom",
				"variant", variant, "paired", names[1-v], "generated", generated, "colors", colors, "semantic", sem)
			files = append(files, File{names[v] + ".json", jsonx.Marshal(theme)})
		}
	}
	return files
}

func title(s string) string { return strings.ToUpper(s[:1]) + s[1:] }
