import QtQuick
import QtTest
import qs.components.methods

TestCase {
  name: "ThemeFamilies"

  function theme(name, label, variant, paired) {
    return {
      "name": name,
      "label": label,
      "variant": variant,
      "paired": paired,
      "preview": null
    };
  }

  readonly property var tokyo: [theme("tokyo-night", "Tokyo Night", "dark", "tokyo-day"), theme("tokyo-storm", "Tokyo Storm", "dark", "tokyo-day"), theme("tokyo-day", "Tokyo Day", "light", "tokyo-night")]

  function test_pair() {
    const families = ThemeFamilies.build([theme("a-dark", "Ayu Dark", "dark", "a-light"), theme("a-light", "Ayu Light", "light", "a-dark")], false);
    compare(families.length, 1);
    compare(families[0].label, "Ayu");
    compare(families[0].dark, "a-dark");
    compare(families[0].light, "a-light");
    compare(families[0].shared, false);
  }

  function test_sharedLight() {
    const families = ThemeFamilies.build(tokyo, false);
    compare(families.map(family => family.label), ["Tokyo", "Tokyo Storm"], "the extra dark keeps its own name");
    compare(families[1].dark, "tokyo-storm");
    compare(families[1].light, "tokyo-day", "and shares the family's light");
    compare(families[1].shared, true);
  }

  function test_loneThemes() {
    const families = ThemeFamilies.build([theme("d", "Dark One", "dark", ""), theme("l", "Light One", "light", "missing"), theme("x", "Odd", "dark", "d")], true);
    compare(families.length, 3, "a dark naming another dark stays alone");
    compare(families.every(family => !(family.dark && family.light)), true);
    compare(families.every(family => family.generated), true);
  }

  function test_halfPair() {
    const families = ThemeFamilies.build([theme("f-dark", "Foo Dark", "dark", "f-light"), theme("f-light", "Foo Light", "light", "")], false);
    compare(families.map(family => family.label), ["Foo Dark", "Foo Light"], "a light naming no dark back joins none");
    compare(families.every(family => !family.shared), true);
    const unanswered = ThemeFamilies.build([theme("g-dark", "Goo Dark", "dark", "g-light"), theme("g-light", "Goo Light", "light", "g-other"), theme("g-other", "Goo Other", "dark", "")], false);
    compare(unanswered.length, 3, "nor does one whose dark doesn't name it");
  }

  function test_current() {
    const families = ThemeFamilies.build(tokyo, false);
    compare(ThemeFamilies.current(families, "tokyo-storm", "").label, "Tokyo Storm");
    compare(ThemeFamilies.current(families, "tokyo-day", "tokyo-storm").label, "Tokyo Storm", "a light remembers the dark it came from");
    compare(ThemeFamilies.current(families, "tokyo-day", "").label, "Tokyo", "else it is its main family's");
    compare(ThemeFamilies.current(families, "nope", ""), null);
  }

  function test_previewOf() {
    const dark = theme("a-dark", "Ayu Dark", "dark", "a-light");
    dark.preview = {
      "background": "#000"
    };
    const light = theme("a-light", "Ayu Light", "light", "a-dark");
    light.preview = {
      "background": "#fff"
    };
    const families = ThemeFamilies.build([dark, light], false);
    compare(ThemeFamilies.previewOf(families, "a-dark").background, "#000");
    compare(ThemeFamilies.previewOf(families, "a-light").background, "#fff", "the light variant's, not its family's dark");
    compare(ThemeFamilies.previewOf(families, "nope"), null);
  }

  function test_commonLabel() {
    compare(ThemeFamilies.commonLabel("Nightfox", "Dayfox"), "Nightfox");
    compare(ThemeFamilies.commonLabel("Rosé Pine", "Rosé Pine Dawn"), "Rosé Pine");
  }
}
