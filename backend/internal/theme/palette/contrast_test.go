package palette

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

// The contrast pairs shared with the shell's Tone (tests/tst_Tone.qml reads
// the same file): the exported WCAG functions agree with the fixture.
func TestContrastFixture(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile("../../../../tests/fixtures/style/contrast.json")
	if err != nil {
		t.Fatal(err)
	}
	var rows []struct {
		A     string  `json:"a"`
		B     string  `json:"b"`
		LumA  float64 `json:"lumA"`
		LumB  float64 `json:"lumB"`
		Ratio float64 `json:"ratio"`
	}
	if err := json.Unmarshal(raw, &rows); err != nil {
		t.Fatal(err)
	}
	if len(rows) != 24 {
		t.Fatalf("%d rows, want 24", len(rows))
	}
	for _, r := range rows {
		if got := Contrast(r.A, r.B); math.Abs(got-r.Ratio) > 0.001 {
			t.Errorf("Contrast(%s, %s) = %.4f, want %.3f", r.A, r.B, got, r.Ratio)
		}
		if got := Luminance(r.A); math.Abs(got-r.LumA) > 1e-6 {
			t.Errorf("Luminance(%s) = %.7f, want %.6f", r.A, got, r.LumA)
		}
		if got := Luminance(r.B); math.Abs(got-r.LumB) > 1e-6 {
			t.Errorf("Luminance(%s) = %.7f, want %.6f", r.B, got, r.LumB)
		}
	}
}
