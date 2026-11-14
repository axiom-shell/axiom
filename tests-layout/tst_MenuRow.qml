import QtQuick
import QtTest
import qs.config
import qs.components.reusable

// MenuRow: its states read their colours from Style (current, lit, danger,
// disabled), its text inherits the ink of the Surface it sits on, a click
// emits `activated`.
TestCase {
  id: root

  name: "MenuRow"
  when: windowShown
  visible: true
  width: 400
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: rowComp

    MenuRow {
      width: 300
      text: "Open file"
      icon: "folder"
    }
  }

  Component {
    id: surfaceComp

    Surface {
      id: surface

      property alias row: inner

      tone: "raised"
      width: 300
      height: 60

      MenuRow {
        id: inner

        width: 300
        text: "Open file"
        icon: "folder"
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function sameColor(actual, expected) {
    // within a quantisation step: a Text keeps its colour in 16 bits
    const near = (a, b) => Math.abs(a - b) < 0.004;
    verify(near(actual.r, expected.r) && near(actual.g, expected.g) && near(actual.b, expected.b) && near(actual.a, expected.a), `${actual} is not ${expected}`);
  }

  function textOf(row) {
    return harness.texts(row).find(t => t.text === row.text);
  }

  function iconOf(row) {
    return harness.texts(row).find(t => t.text === row.icon);
  }

  function test_plain_row() {
    const row = createTemporaryObject(rowComp, root);
    compare(row.implicitHeight, Widget.height);
    sameColor(textOf(row).color, Style.text);
    sameColor(iconOf(row).color, Style.textMuted);
  }

  function test_current_reads_the_container_ink() {
    const row = createTemporaryObject(rowComp, root, {
      "current": true
    });
    sameColor(textOf(row).color, Style.inkAccentContainer.text);
    sameColor(iconOf(row).color, Style.inkAccentContainer.text);
  }

  function test_danger_and_disabled() {
    const danger = createTemporaryObject(rowComp, root, {
      "danger": true
    });
    sameColor(textOf(danger).color, Style.errorText);
    const off = createTemporaryObject(rowComp, root, {
      "enabled": false
    });
    sameColor(textOf(off).color, Style.textDisabled);
    sameColor(iconOf(off).color, Style.textDisabled);
  }

  function test_inherits_the_surface_ink() {
    const surface = createTemporaryObject(surfaceComp, root);
    sameColor(textOf(surface.row).color, surface.ink.text);
    sameColor(iconOf(surface.row).color, surface.ink.muted);
    surface.row.current = true;
    sameColor(textOf(surface.row).color, Style.inkAccentContainer.text);
    surface.row.current = false;
    sameColor(textOf(surface.row).color, surface.ink.text);
  }

  function test_lit_and_hovered_tint_the_layer() {
    const row = createTemporaryObject(rowComp, root);
    const layer = row.children.find(c => c.bleed !== undefined);
    sameColor(layer.color, Style.stateRest);
    row.lit = true;
    tryVerify(() => Math.abs(layer.color.a - Style.stateHover.a) < 0.004);
  }

  function test_click_activates() {
    const row = createTemporaryObject(rowComp, root);
    const spy = createTemporaryObject(spyComp, root, {
      "target": row
    });
    mouseClick(row);
    compare(spy.count, 1);
    row.enabled = false;
    mouseClick(row);
    compare(spy.count, 1);
  }

  Component {
    id: spyComp

    SignalSpy {
      signalName: "activated"
    }
  }
}
