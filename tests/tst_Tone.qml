import QtQuick
import QtTest
import qs.components.methods

// The shell's colour math (Tone): exact rows for the small functions, the
// nudging and bisecting ones against what they promise, and the contrast
// fixture shared with the Go side (tests/fixtures/style/contrast.json).
TestCase {
  id: root

  name: "Tone"

  RepoFiles {
    id: files
  }

  function same(actual, expected, message) {
    verify(Qt.colorEqual(actual, expected), `${message}: ${actual} != ${expected}`);
  }

  // Equal to within 8-bit rounding
  function close(actual, expected, message) {
    const a = Qt.color(actual), e = Qt.color(expected);
    verify(Math.abs(a.r - e.r) < 0.01 && Math.abs(a.g - e.g) < 0.01 && Math.abs(a.b - e.b) < 0.01 && Math.abs(a.a - e.a) < 0.01, `${message}: ${actual} != ${expected}`);
  }

  // `ink` reads at `min` on `fill` at alpha `a` over `back`, in floats (a
  // Qt color's alpha is 8 bits)
  function readsAt(fill, ink, back, a, min) {
    return Tone.conRgb(Tone.rgb(ink), Tone.mixRgb(Tone.rgb(back), Tone.rgb(fill), a)) >= min;
  }

  function test_mix() {
    same(Tone.mix("#000000", "#ffffff", 0), "#000000", "t 0 is a");
    same(Tone.mix("#000000", "#ffffff", 1), "#ffffff", "t 1 is b");
    close(Tone.mix("#000000", "#ffffff", 0.5), "#808080", "the middle");
    close(Tone.mix(Qt.rgba(1, 0, 0, 0), Qt.rgba(1, 0, 0, 1), 0.5), Qt.rgba(1, 0, 0, 0.5), "alpha mixes too");
  }

  function test_over() {
    same(Tone.over("#ffffff", "#000000"), "#ffffff", "opaque top");
    close(Tone.over("#80ffffff", "#000000"), "#808080", "half white over black");
    same(Tone.over("#00ffffff", "#336699"), "#336699", "clear top");
    compare(Tone.over("#80ffffff", "#000000").a, 1, "always opaque");
  }

  function test_alpha() {
    close(Tone.alpha("#ff0000", 0.5), "#80ff0000", "alpha set");
    close(Tone.alpha("#40ff0000", 1), "#ff0000", "replaces, not multiplies");
  }

  function test_faded() {
    close(Tone.faded("#ff0000", 0.5), "#80ff0000", "an opaque color halves");
    close(Tone.faded("#80ff0000", 0.5), "#40ff0000", "of its own opacity");
    compare(Tone.faded("transparent", 0.5).a, 0, "a clear color stays clear");
    compare(Qt.color(Tone.faded("#00336699", 0.5)).b, Qt.color("#336699").b, "and keeps its channels");
  }

  function test_toward() {
    close(Tone.toward("#000000", "#ffffff", 0.5), "#808080", "mixed");
    close(Tone.toward("#80000000", "#ffffff", 0.5), "#80808080", "alpha kept");
    compare(Tone.toward("transparent", "#ffffff", 0.5), "transparent", "a clear color stays clear");
  }

  function test_luminance() {
    compare(Tone.luminance("#000000"), 0);
    fuzzyCompare(Tone.luminance("#ffffff"), 1, 0.000001);
    verify(Tone.luminance("#808080") > 0.2 && Tone.luminance("#808080") < 0.22, "mid grey");
  }

  function test_contrast() {
    fuzzyCompare(Tone.contrast("#000000", "#ffffff"), 21, 0.001, "black on white");
    fuzzyCompare(Tone.contrast("#777777", "#777777"), 1, 0.000001, "same colour");
    fuzzyCompare(Tone.contrast("#123456", "#fedcba"), Tone.contrast("#fedcba", "#123456"), 0.000001, "symmetric");
  }

  function test_contrast_fixture() {
    const rows = files.json("tests/fixtures/style/contrast.json");
    compare(rows.length, 24);
    for (const row of rows) {
      verify(Math.abs(Tone.contrast(row.a, row.b) - row.ratio) < 0.001, `${row.a} / ${row.b}: ${Tone.contrast(row.a, row.b)} != ${row.ratio}`);
      verify(Math.abs(Tone.luminance(row.a) - row.lumA) < 0.000001, `${row.a}: ${Tone.luminance(row.a)} != ${row.lumA}`);
      verify(Math.abs(Tone.luminance(row.b) - row.lumB) < 0.000001, `${row.b}: ${Tone.luminance(row.b)} != ${row.lumB}`);
    }
  }

  function test_nudged() {
    same(Tone.nudged(["#000000"], "#ffffff", 4.5), "#ffffff", "already reading: unchanged");
    const dim = Tone.nudged(["#000000"], "#202830", 4.5);
    const ratio = Tone.contrast(dim, "#000000");
    verify(ratio >= 4.5 && ratio < 4.55, `a dark colour on black is lightened just past the minimum: ${ratio}`);
    verify(Tone.luminance(dim) > Tone.luminance("#202830"), "lightened");
    same(Tone.nudged(["#777777"], "#787878", 21), "#000000", "impossible target: the pole that reads best");
    const both = Tone.nudged(["#000000", "#ffffff"], "#808080", 4.5);
    verify(Tone.contrast(both, "#000000") < 4.5 || Tone.contrast(both, "#ffffff") < 4.5, "no colour reads on both ends: the pole");
    close(Tone.nudged(["#000000"], "#20336699", 4.5), Qt.alpha(Tone.nudged(["#000000"], "#336699", 4.5), 0.125), "alpha kept");
    compare(Tone.nudged(["#000000"], "transparent", 4.5), "transparent", "a clear colour stays as it is");
  }

  // apart and step return exact colours; reading one back through Qt.color
  // rounds it to 8 bits, hence the 0.05 under `min` in these rows
  function test_apart() {
    same(Tone.apart("#000000", "#ffffff", 4.5, "#ffffff"), "#ffffff", "already apart: unchanged");
    const moved = Tone.apart("#808080", "#808080", 1.3, "#ffffff");
    const ratio = Tone.contrast("#808080", moved);
    verify(ratio >= 1.3 - 0.05 && ratio < 1.33, `equal colours are moved until min: ${ratio}`);
    verify(Tone.luminance(moved) > Tone.luminance("#808080"), "toward the pole");
    const dark = Tone.apart("#808080", "#808080", 1.3, "#000000");
    verify(Tone.luminance(dark) < Tone.luminance("#808080"), "the other pole");
  }

  function test_step() {
    // the page and card of a dark theme: capped at max, then at least min
    const capped = Tone.step("#1e1e2e", "#ffffff", 1.1, 1.3, "#ffffff");
    const ratio = Tone.contrast("#1e1e2e", capped);
    verify(ratio >= 1.1 - 0.05 && ratio <= 1.35, `capped at max: ${ratio}`);
    const raised = Tone.step("#1e1e2e", "#1e1e2e", 1.2, 1.6, "#ffffff");
    verify(Tone.contrast("#1e1e2e", raised) >= 1.2 - 0.05, "an equal target is lifted to min");
    const near = Tone.step("#1e1e2e", "#222233", 1.2, 1.6, "#ffffff");
    verify(Tone.contrast("#1e1e2e", near) >= 1.2 - 0.05, "a too-near target is lifted to min");
  }

  function test_readableOn() {
    same(Tone.readableOn("#000000", "#cccccc", ["#ffffff"]), "#cccccc", "the preferred where it reads");
    same(Tone.readableOn("#ffffff", "#eeeeee", ["#222222"]), "#000000", "black beats an alternate that reads less");
    same(Tone.readableOn("#808080", "#808080", []), "#000000", "black on a light-ish grey");
    same(Tone.readableOn("#555555", "#555555", ["#cccccc"]), "#FFFFFF", "white on a dark grey");
    same(Tone.readableOn("#ffffff", "#777777", ["#000000"]), "#000000", "an alternate as good as black is taken first");
  }

  function test_bestOn() {
    compare(Tone.bestOn("#000000"), "#FFFFFF");
    compare(Tone.bestOn("#ffffff"), "#000000");
    compare(Tone.bestOn("#fb4934"), "#000000", "by contrast, not by a luma split");
    compare(Tone.bestOn("#3060c0"), "#FFFFFF");
  }

  function test_isDark() {
    verify(Tone.isDark("#101010"));
    verify(!Tone.isDark("#f0f0f0"));
    verify(!Tone.isDark("#00a800"), "WCAG: white and black both read about alike; black wins on this green");
  }

  function test_reaches() {
    verify(Tone.reaches(["#000000", "#101010"], "#ffffff", 4.5), "reads on every back");
    verify(!Tone.reaches(["#000000", "#ffffff"], "#808080", 4.5), "not on one of them");
    verify(Tone.reaches([], "#808080", 21), "no backs: vacuously");
  }

  function test_alphaFloor() {
    compare(Tone.alphaFloor("#000000", "#ffffff", ["#000000"], 4.5), 0, "already reads on the bare backs");
    compare(Tone.alphaFloor("#808080", "#808080", ["#ffffff"], 4.5), 1, "unreachable even on the opaque fill");
    // text over the page over the pole: the pole rows of tokens_reference.py --scrims
    const rows = [["catppuccin-mocha", 0.73], ["catppuccin-latte", 0.82], ["gruvbox-dark", 0.81], ["tokyo-night", 0.75]];
    const defaults = files.json("qml/config/json/theme-defaults.json");
    for (const [name, expected] of rows) {
      const roles = StyleTokens.derive(StyleTokens.theme(files.json(`qml/config/themes/${name}.json`), defaults));
      const pole = roles.dark ? "#ffffff" : "#000000";
      const min = Tone.textContrast + StyleTokens.margin;
      const a = Tone.alphaFloor(roles.surfacePage, roles.text, [pole], min);
      verify(Math.abs(a - expected) <= 0.01, `${name}: ${a} != ${expected}`);
      verify(root.readsAt(roles.surfacePage, roles.text, pole, a, min), `${name}: reaches min`);
      verify(!root.readsAt(roles.surfacePage, roles.text, pole, a - 0.01, min), `${name}: 0.01 less does not`);
    }
    // on every back at once
    const backs = ["#000000", "#808080", "#ffffff"];
    const both = Tone.alphaFloor("#1e1e2e", "#cdd6f4", backs, 4.5);
    verify(both > 0 && both < 1, `${both}`);
    for (const b of backs)
      verify(root.readsAt("#1e1e2e", "#cdd6f4", b, both, 4.5), `reaches on ${b}`);
  }
}
