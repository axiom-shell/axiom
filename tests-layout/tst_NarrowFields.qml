import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.forms
import qs.components.reusable
import qs.components.methods

// Schema fields at narrow and wide widths (FieldLine, FieldFit): a short
// control stays on its label's line when the line fits beside it, so a
// narrow form reads like the settings page; the description stays beside the
// control at any width (wrapping earlier), the control centred on the whole
// box; a toggle that has to stack fills the width. A row inside a depth-2 block is placed by its own
// body width. Wide layouts keep their geometry.
TestCase {
  id: root

  name: "NarrowFields"
  when: windowShown
  visible: true
  width: 700
  height: 700

  Harness {
    id: harness
  }

  readonly property string note: "Empty: monospace when on, else the module's, else the shell's."

  Component {
    id: switchComp
    SchemaSwitch {
      label: "Enabled"
      checked: false
    }
  }

  Component {
    id: comboComp
    SchemaComboBox {
      label: "Color"
      options: ["", "primary"]
      currentValue: ""
    }
  }

  Component {
    id: toggleComp
    SchemaToggle {
      label: "Mode"
      options: ["icon", "text", "both"]
      optionLabels: ({
          "icon": "Icon",
          "text": "Text",
          "both": "Both"
        })
      currentValue: "icon"
    }
  }

  Component {
    id: stepperComp
    SchemaNumberField {
      label: "Size"
      mode: "stepper"
      minimum: 0
      maximum: 100
      currentConfigValue: 50
    }
  }

  Component {
    id: sliderComp
    SchemaNumberField {
      label: "Size"
      mode: "slider"
      minimum: 0
      maximum: 100
      currentConfigValue: 50
    }
  }

  Component {
    id: textComp
    SchemaTextField {
      label: "Name"
      currentConfigValue: "x"
    }
  }

  // A row two levels deep (depth 2)
  Component {
    id: nestedComp
    Item {
      property alias row: row
      property alias combo: combo
      width: Widget.textPx(300)
      height: 200

      FormRow {
        id: row
        width: parent.width
        level: 2
        first: true
        bodyHeight: combo.implicitHeight

        SchemaComboBox {
          id: combo
          width: parent.width
          label: "Color"
          options: ["", "primary"]
          currentValue: ""
        }
      }
    }
  }

  function rows() {
    const out = [];
    for (const scale of [100, 150])
      for (const density of ["compact", "normal", "roomy"])
        out.push({
          "tag": `${scale}% ${density}`,
          "scale": scale,
          "density": density
        });
    return out;
  }

  function findAll(item, pred) {
    const out = [];
    const walk = it => {
      if (pred(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  function entryOf(field) {
    return findAll(field, it => it.options !== undefined && it.listOpen !== undefined)[0];
  }

  function textOf(field, text) {
    return findAll(field, it => it.text !== undefined && String(it.text).indexOf(text) === 0 && it.visible)[0];
  }

  function centre(item, field) {
    return item.mapToItem(field, 0, item.height / 2).y;
  }

  function make(comp, width, props) {
    const field = createTemporaryObject(comp, root, Object.assign({
      "width": width
    }, props ?? {}));
    waitForRendering(field);
    return field;
  }

  function test_combo_narrow_keeps_its_line_data() {
    return rows();
  }

  function test_combo_narrow_keeps_its_line(data) {
    harness.configure(data);
    const field = make(comboComp, Widget.textPx(300));
    const entry = entryOf(field);
    const label = textOf(field, "Color");
    verify(field.fit.inline, "on the label's line");
    compare(field.implicitHeight, Widget.height, `one control line ${entryOf(field).height}`);
    verify(Math.abs(centre(entry, field) - centre(label, field)) <= 1, "centred on the label");
    verify(Math.abs(entry.mapToItem(field, entry.width, 0).x - field.width) <= 0.5, "at the line's end");
    compare(entry.width, field.fit.controlWidth);
    compare(harness.containedProblems(field), []);
  }

  // The description stays beside the control at every width, the control
  // centred on the whole box at the field's right edge
  function test_description_stays_beside_the_control_data() {
    const out = [];
    for (const r of rows())
      for (const kind of ["switch", "toggle", "combo"])
        for (const w of [300, 380, 540])
          out.push(Object.assign({}, r, {
            "tag": `${kind} ${w} ${r.tag}`,
            "kind": kind,
            "w": w
          }));
    return out;
  }

  function test_description_stays_beside_the_control(data) {
    harness.configure(data);
    const comp = data.kind === "switch" ? switchComp : data.kind === "toggle" ? toggleComp : comboComp;
    const field = make(comp, Widget.textPx(data.w), {
      "description": note
    });
    const control = data.kind === "switch" ? findAll(field, it => it.checked !== undefined && it.toggled !== undefined && it !== field)[0] : data.kind === "toggle" ? findAll(field, it => it._segment !== undefined)[0] : entryOf(field);
    const desc = textOf(field, "Empty:");
    verify(field.fit.inline, "the control is on the label's line");
    verify(control && desc);
    verify(Math.abs(centre(control, field) - field.height / 2) <= 1, `centred on the whole box: ${centre(control, field)} vs ${field.height / 2}`);
    verify(Math.abs(control.mapToItem(field, control.width, 0).x - field.width) <= 0.5, "at the field's right edge");
    verify(Math.abs(desc.mapToItem(field, 0, 0).x) <= 0.5, "description at the left");
    verify(desc.mapToItem(field, desc.width, 0).x <= control.mapToItem(field, 0, 0).x + 0.5, "description left of the control");
    if (data.w === 300)
      verify(desc.height > textOf(field, data.kind === "switch" ? "Enabled" : data.kind === "toggle" ? "Mode" : "Color").height * 1.5, `wraps to several lines: ${desc.height}`);
    compare(harness.containedProblems(field), []);
  }

  function test_combo_wide_is_unchanged_data() {
    return rows();
  }

  function test_combo_wide_is_unchanged(data) {
    harness.configure(data);
    const field = make(comboComp, Widget.textPx(540), {
      "description": note
    });
    const entry = entryOf(field);
    const desc = textOf(field, "Empty:");
    verify(field.fit.inline);
    compare(entry.width, Math.round(Math.min(Widget.textPx(260), Widget.textPx(540) * 0.42)));
    verify(Math.abs(entry.mapToItem(field, entry.width, 0).x - field.width) <= 0.5);
    verify(Math.abs(desc.mapToItem(field, 0, 0).x) <= 0.5);
    verify(desc.mapToItem(field, desc.width, 0).x <= entry.mapToItem(field, 0, 0).x + 0.5, "the description stays left of the box");
    compare(harness.containedProblems(field), []);
  }

  function test_toggle_narrow_keeps_its_line_data() {
    return rows();
  }

  function test_toggle_narrow_keeps_its_line(data) {
    harness.configure(data);
    const field = make(toggleComp, Widget.textPx(300));
    const toggle = findAll(field, it => it._segment !== undefined)[0];
    verify(!field.stacked, "beside the label");
    const label = textOf(field, "Mode");
    verify(Math.abs(centre(toggle, field) - centre(label, field)) <= 1);
    verify(field.implicitHeight <= Widget.height, "one control line");
    compare(harness.containedProblems(field), []);
  }

  function test_stacked_toggle_fills_the_width_data() {
    return rows();
  }

  function test_stacked_toggle_fills_the_width(data) {
    harness.configure(data);
    const field = make(toggleComp, Widget.textPx(200), {
      "label": "A label thirty characters long"
    });
    const toggle = findAll(field, it => it._segment !== undefined)[0];
    verify(field.stacked);
    verify(Math.abs(toggle.width - field.width) <= 0.5, `${toggle.width} of ${field.width}`);
  }

  function test_stepper_narrow_keeps_its_line_data() {
    return rows();
  }

  function test_stepper_narrow_keeps_its_line(data) {
    harness.configure(data);
    const field = make(stepperComp, Widget.textPx(300));
    const stepper = findAll(field, it => it.tone === "sunken" && it.children.some(c => c.spacing === 2))[0];
    const label = textOf(field, "Size");
    verify(field.inline);
    verify(Math.abs(centre(stepper, field) - centre(label, field)) <= 1);
    verify(Math.abs(stepper.mapToItem(field, stepper.width, 0).x - field.width) <= 0.5, "at the line's end");
    compare(harness.containedProblems(field), []);
  }

  function test_slider_needs_its_width_data() {
    return rows();
  }

  function test_slider_needs_its_width(data) {
    harness.configure(data);
    const narrow = make(sliderComp, Widget.textPx(300));
    verify(!narrow.inline, "a slider needs travel: stacked");
    const slider = findAll(narrow, it => it.fillTone !== undefined)[0];
    verify(slider.parent.width >= narrow.width - 1, "filling");
    compare(harness.containedProblems(narrow), []);
    const wide = make(sliderComp, Widget.textPx(540));
    verify(wide.inline);
    compare(harness.containedProblems(wide), []);
  }

  function test_text_field_stays_under_its_label_data() {
    return rows();
  }

  function test_text_field_stays_under_its_label(data) {
    harness.configure(data);
    for (const w of [Widget.textPx(300), Widget.textPx(540)]) {
      const field = make(textComp, w);
      verify(!field.fit.inline);
      compare(harness.containedProblems(field), []);
    }
  }

  // Resizing narrow to wide in place flips every cell together
  function test_resize_flips_cleanly() {
    harness.configure({});
    const field = make(comboComp, Widget.textPx(120), {
      "description": note
    });
    verify(!field.fit.inline);
    field.width = Widget.textPx(540);
    waitForRendering(field);
    verify(field.fit.inline);
    const entry = entryOf(field);
    verify(Math.abs(entry.mapToItem(field, entry.width, 0).x - field.width) <= 0.5);
    field.width = Widget.textPx(300);
    waitForRendering(field);
    verify(field.fit.inline);
    compare(harness.containedProblems(field), []);
  }

  // At depth 2 the row's body is two steps narrower: the field is placed by
  // that width, not the row's
  function test_depth_two_row_is_placed_by_its_body_width_data() {
    return rows();
  }

  function test_depth_two_row_is_placed_by_its_body_width(data) {
    harness.configure(data);
    const host = make(nestedComp, Widget.textPx(300));
    const combo = host.combo;
    compare(host.row.depth, 2);
    verify(Math.abs(combo.width - (host.width - host.row.indent)) <= 0.5, `${combo.width} of ${host.width}, indent ${host.row.indent}`);
    const expected = FieldFit.place("flex", combo.width, findAll(combo, it => it.lineWidth !== undefined)[0].lineWidth, 0, Widget.fieldTokens);
    compare(combo.fit.inline, expected.inline);
    compare(combo.fit.controlWidth, expected.controlWidth);
    const entry = entryOf(combo);
    verify(expected.inline, "a short label still fits beside the box");
    verify(Math.abs(centre(entry, combo) - centre(textOf(combo, "Color"), combo)) <= 1);
    compare(combo.implicitHeight, Widget.height);
  }
}
