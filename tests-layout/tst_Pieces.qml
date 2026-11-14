import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.forms
import qs.components.methods

// The restyled pieces at scale, font and density (the layout harness): each
// holds its texts in its box, a control's label fits its control, a segment
// or toggle shows every label whole, a chip keeps its floor.
TestCase {
  id: root

  name: "Pieces"
  when: windowShown
  visible: true
  width: 700
  height: 500

  Harness {
    id: harness
  }

  readonly property var strings: ({
      "en": "Open settings",
      "ja": "設定を開く",
      "token": "a".repeat(30)
    })

  Component {
    id: buttonComp

    StyledTextButton {
      iconText: "add"
    }
  }

  Component {
    id: squeezeComp

    RowLayout {
      property alias button: inner

      height: 100

      StyledTextButton {
        id: inner

        iconText: "add"
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 2000
      }
    }
  }

  Component {
    id: segmentComp

    SegmentRow {
      property var labels: []

      Repeater {
        model: labels

        SegmentButton {
          required property int index
          required property string modelData

          text: modelData
          active: index === 1
        }
      }
    }
  }

  Component {
    id: iconSegmentComp

    SegmentButton {
      iconText: "visibility_off"
    }
  }

  Component {
    id: toggleComp

    StyledToggle {
      options: ["a", "b", "c"]
      value: "b"
    }
  }

  Component {
    id: chipComp

    StatusChip {
      tone: "success"
    }
  }

  Component {
    id: keyHintComp

    KeyHint {
      key: "Ctrl+O"
    }
  }

  Component {
    id: listRowComp

    ColumnLayout {
      property alias row: inner

      ListEntryRow {
        id: inner

        icon: "folder"
      }
    }
  }

  Component {
    id: tabBarComp

    StyledTabBar {
      tabs: ["First", "Second", "Third"]
      currentIndex: 1
    }
  }

  Component {
    id: tileComp

    ActionTile {
      icon: "wifi"
      showLabel: true
    }
  }

  Component {
    id: pillComp

    ActionPill {
      icon: "wifi"
      status: "Connected"
    }
  }

  Component {
    id: iconButtonComp

    StyledIconButton {
      iconText: "close"
    }
  }

  Component {
    id: groupComp

    FieldGroup {
      title: "A group"
      description: "What it holds"

      StyledText {
        text: "A field"
      }
    }
  }

  Component {
    id: hostComp

    Surface {
      property alias group: inner

      width: 400
      height: 200

      FieldGroup {
        id: inner

        title: "A group"
        width: 380

        StyledText {
          text: "A field"
        }
      }
    }
  }

  Component {
    id: headerComp

    FieldHeader {
      description: "What the field does, in a sentence"
    }
  }

  Component {
    id: schemaToggleComp

    SchemaToggle {
      description: "What it does"
      options: ["a", "b"]
      optionLabels: ({
          "a": "First option",
          "b": "Second option"
        })
      currentValue: "a"
    }
  }

  Component {
    id: formRowComp

    FormRow {
      id: formRow

      property alias spy: clicks

      width: 300
      bodyHeight: 10

      SignalSpy {
        id: clicks

        target: formRow
        signalName: "rowClicked"
      }
    }
  }

  Component {
    id: numberComp

    SchemaNumberField {
      label: "A number"
      minimum: 0
      maximum: 100
      currentConfigValue: 50
    }
  }

  Component {
    id: foldHeaderComp

    FoldHeader {
      width: 400
      title: "Group"
      status: "On"
    }
  }

  Component {
    id: clampedComp

    ClampedText {
      maxLines: 2
    }
  }

  Component {
    id: noIconButtonComp

    StyledTextButton {
      text: "Plain"
    }
  }

  Component {
    id: relayComp

    Surface {
      property alias loader: streamed

      tone: "raised"
      width: 300
      height: 100

      StreamedLoader {
        id: streamed

        stream: false
        sourceComponent: StyledText {
          text: "Inside"
        }
      }
    }
  }

  Component {
    id: zoomRelayComp

    Item {
      id: zoomHost

      property alias text: inner

      property real contentZoom: 0.5
      readonly property real drawnZoom: zoomHost.contentZoom * TextRender.zoomAt(zoomHost.parent)
      readonly property var inkHostAbove: InkHost.find(zoomHost.parent)

      StyledText {
        id: inner

        text: "Zoomed"
      }
    }
  }

  function initTestCase() {
    harness.configure({});
  }

  function rows() {
    const out = [];
    for (const scale of [75, 150])
      for (const fontSize of [8, 14, 32])
        for (const width of ["narrow", "wide"])
          for (const key of ["en", "ja", "token"])
            out.push({
              "tag": `${scale}% font ${fontSize} ${width} ${key}`,
              "scale": scale,
              "fontSize": fontSize,
              "density": "normal",
              "width": width,
              "key": key
            });
    return out;
  }

  // A tooltip-free measure of room: narrow holds about 14 characters, wide 50
  function room(data) {
    return data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400);
  }

  function test_button_holds_its_label_data() {
    return rows();
  }

  function test_button_holds_its_label(data) {
    harness.configure(data);
    const button = createTemporaryObject(buttonComp, root, {
      "text": strings[data.key]
    });
    waitForRendering(button);
    compare(harness.containedProblems(button), []);
    verify(button.implicitHeight >= Widget.height, "at least a control's height");
    for (const t of harness.texts(button)) {
      if (t.text === button.text)
        compare(t.lineCount, 1);
    }
  }

  // Squeezed in a row, a button keeps the width its label needs
  function test_button_is_never_squeezed_data() {
    return rows();
  }

  function test_button_is_never_squeezed(data) {
    harness.configure(data);
    const row = createTemporaryObject(squeezeComp, root, {
      "width": room(data)
    });
    row.button.text = strings[data.key];
    waitForRendering(row);
    verify(row.button.width >= row.button.implicitWidth - 0.5, `${row.button.width} < ${row.button.implicitWidth}`);
    compare(harness.containedProblems(row.button), []);
  }

  // overflow "line": a capped button may go under its label, which then elides
  function test_button_elides_when_asked() {
    harness.configure({});
    const row = createTemporaryObject(squeezeComp, root, {
      "width": Widget.px(60)
    });
    row.button.overflow = "line";
    row.button.Layout.fillWidth = true;
    row.button.text = "abcdefghijklmnopqrstuvwxyzabcdefghijklmn";
    waitForRendering(row);
    verify(row.button.width < row.button.implicitWidth, `${row.button.width} >= ${row.button.implicitWidth}`);
    compare(harness.containedProblems(row.button), []);
  }

  function test_button_kinds_read_their_ink() {
    harness.configure({});
    for (const kind of ["tonal", "primary", "danger", "dangerPrimary"]) {
      const button = createTemporaryObject(buttonComp, root, {
        "text": "Label",
        "kind": kind
      });
      const label = harness.texts(button).find(t => t.text === "Label");
      const ink = kind === "tonal" ? Style.inkHighest : kind === "primary" ? Style.inkAccent : kind === "danger" ? Style.inkErrorContainer : Style.inkError;
      compare(label.color.toString(), Qt.color(ink.text).toString(), kind);
    }
  }

  function test_segment_row_shows_every_label_data() {
    return rows();
  }

  function test_segment_row_shows_every_label(data) {
    harness.configure(data);
    const labels = [strings[data.key], "b", "c"];
    const row = createTemporaryObject(segmentComp, root, {
      "labels": labels
    });
    // a form row stacks the control under its label when its room is less
    // than `implicitWidth`: given at least that, nothing elides
    row.width = Math.max(room(data), row.implicitWidth);
    waitForRendering(row);
    verify(row.implicitWidth > 0);
    const texts = harness.texts(row);
    compare(texts.length, 3);
    for (const t of texts)
      verify(!t.truncated, `"${t.text}" is elided`);
    compare(harness.containedProblems(row), []);
    // equal segments, as wide as the widest label
    const widths = Array.prototype.filter.call(row.children[1].children, c => c.width > 0).map(c => Math.round(c.width));
    verify(widths.every(w => Math.abs(w - widths[0]) <= 1), `unequal segments ${widths}`);
  }

  function test_segment_button_holds_icon_and_label_data() {
    return rows();
  }

  function test_segment_button_holds_icon_and_label(data) {
    harness.configure(data);
    // no Layout parent (a Flow's case): width = implicitWidth
    const button = createTemporaryObject(iconSegmentComp, root, {
      "text": strings[data.key]
    });
    waitForRendering(button);
    for (const t of harness.texts(button))
      verify(!t.truncated, `"${t.text}" is elided`);
    compare(harness.containedProblems(button), []);
  }

  function test_toggle_shows_every_label_data() {
    return rows();
  }

  function test_toggle_shows_every_label(data) {
    harness.configure(data);
    const toggle = createTemporaryObject(toggleComp, root, {
      "labels": ({
          "a": strings[data.key],
          "b": "B",
          "c": "C"
        })
    });
    waitForRendering(toggle);
    for (const t of harness.texts(toggle))
      verify(!t.truncated, `"${t.text}" is elided`);
    compare(harness.containedProblems(toggle), []);
  }

  function test_chip_floor_data() {
    return rows();
  }

  function test_chip_floor(data) {
    harness.configure(data);
    const chip = createTemporaryObject(chipComp, root, {
      "text": strings[data.key]
    });
    waitForRendering(chip);
    verify(chip.height >= Widget.smallHeight, "the chip floor");
    compare(harness.containedProblems(chip), []);
    for (const t of harness.texts(chip))
      verify(!t.truncated, "a chip never elides its word");
    const hint = createTemporaryObject(keyHintComp, root, {
      "label": strings[data.key]
    });
    waitForRendering(hint);
    compare(harness.containedProblems(hint), []);
  }

  function test_list_row_holds_its_label_data() {
    return rows();
  }

  function test_list_row_holds_its_label(data) {
    harness.configure(data);
    const host = createTemporaryObject(listRowComp, root, {
      "width": room(data)
    });
    const row = host.row;
    row.label = strings[data.key];
    waitForRendering(host);
    compare(harness.containedProblems(row), []);
    verify(!row.revealed, "actions hidden at rest");
    row.selected = true;
    verify(row.revealed, "actions shown while selected");
  }

  function test_tab_bar_underline_data() {
    return rows();
  }

  function test_tab_bar_underline(data) {
    harness.configure(data);
    const bar = createTemporaryObject(tabBarComp, root, {
      "width": room(data) + Widget.textPx(120)
    });
    waitForRendering(bar);
    tryVerify(() => bar._current !== null && bar._markWidth > 0);
    const tab = bar._current;
    const label = tab.contentItem;
    const underline = bar.children.find(c => c.height === Widget.px(2) && c.visible);
    verify(underline !== undefined, "the underline shows");
    // under the current label, no wider than its cell
    const centre = underline.x + underline.width / 2;
    verify(Math.abs(centre - (tab.x + tab.width / 2)) <= 1, "centred under the current tab");
    verify(underline.width <= tab.width + 0.5);
    verify(underline.width >= Math.min(tab.width, label.implicitWidth) - 0.5, "as wide as the label");
    compare(harness.containedProblems(bar), []);
  }

  function test_tiles_hold_their_text_data() {
    return rows();
  }

  function test_tiles_hold_their_text(data) {
    harness.configure(data);
    const side = Math.max(Widget.textPx(110), Math.round(Appearance.fontSize * 7));
    const tile = createTemporaryObject(tileComp, root, {
      "label": strings[data.key],
      "width": side,
      "height": side
    });
    waitForRendering(tile);
    compare(harness.containedProblems(tile), []);
    const pill = createTemporaryObject(pillComp, root, {
      "label": strings[data.key],
      "width": Widget.textPx(260),
      "height": Math.round(Widget.height * 1.8)
    });
    waitForRendering(pill);
    compare(harness.containedProblems(pill), []);
  }

  function test_icon_button_is_a_square_that_holds_its_icon() {
    for (const fontSize of [8, 14, 32]) {
      harness.configure({
        "fontSize": fontSize
      });
      const button = createTemporaryObject(iconButtonComp, root, {});
      waitForRendering(button);
      compare(button.width, button.height);
      verify(button.width >= Widget.height - 0.5 || button.width === Widget.iconButton);
      compare(button.focusPolicy, Qt.TabFocus);
    }
  }

  // A titled group is a boxed card: surface on the page or with no Surface,
  // flat (the host's fill and ink) on any other
  function test_field_group_is_boxed() {
    harness.configure({});
    const alone = createTemporaryObject(groupComp, root, {
      "width": 400
    });
    waitForRendering(alone);
    compare(alone.tone, "surface");
    compare(alone.border.width, Style.hairline);
    compare(harness.containedProblems(alone), []);
    verify(alone.implicitHeight >= Style.space3 * 2 + alone.children[0].implicitHeight - 0.5);
    for (const tone of ["page", "surface", "raised"]) {
      const host = createTemporaryObject(hostComp, root, {
        "tone": tone
      });
      waitForRendering(host);
      compare(host.group.tone, tone === "page" ? "surface" : tone, tone);
      if (tone === "page") {
        compare(host.group.border.width, Style.hairline);
      } else {
        compare(host.group.color.a, 0, tone);
        compare(host.group.border.width, 0, tone);
        compare(host.group.ink, host.ink, tone);
      }
    }
  }

  function test_field_header_holds_its_text_data() {
    return rows();
  }

  function test_field_header_holds_its_text(data) {
    harness.configure(data);
    const host = createTemporaryObject(headerComp, root, {
      "width": room(data),
      "label": strings[data.key]
    });
    waitForRendering(host);
    compare(harness.containedProblems(host), []);
  }

  function test_schema_toggle_stacks_when_it_crowds_its_label_data() {
    return rows();
  }

  function test_schema_toggle_stacks_when_it_crowds_its_label(data) {
    harness.configure(data);
    const toggle = createTemporaryObject(schemaToggleComp, root, {
      "width": room(data),
      "label": strings[data.key]
    });
    waitForRendering(toggle);
    const control = toggle.children[0].children.find(c => c.options !== undefined);
    compare(toggle.stacked, control.implicitWidth > toggle.width - Widget.textPx(160));
    // A toggle wider than the whole row (a few long labels in a narrow
    // form) overflows however it is laid out: only a fitting one is held
    if (control.implicitWidth <= toggle.width)
      compare(harness.containedProblems(toggle), []);
  }

  // A row of the boxed list: its body padded, never under a row's height,
  // its divider on the top boundary (none on the top row), whole-row clicks
  // only while hoverable
  function test_form_row_is_a_boxed_list_row() {
    harness.configure({});
    const row = createTemporaryObject(formRowComp, root);
    waitForRendering(row);
    compare(row.implicitHeight, Math.max(Style.rowHeight, 10 + Style.rowPadding * 2));
    const divider = row.children.find(c => c.height === Style.dividerWidth);
    verify(divider.visible && divider.y === 0, "the divider sits on the top boundary");
    row.first = true;
    verify(!divider.visible, "none above the top row");
    row.bodyHeight = Style.rowHeight * 2;
    compare(row.implicitHeight, Style.rowHeight * 2 + Style.rowPadding * 2);
    mouseClick(row, 10, row.height / 2);
    compare(row.spy.count, 0);
    row.hoverable = true;
    mouseClick(row, 10, row.height / 2);
    compare(row.spy.count, 1);
    // Only the first hitHeight of the body takes the row click
    row.hitHeight = 20;
    mouseClick(row, 10, row.height - 2);
    compare(row.spy.count, 1);
    mouseClick(row, 10, Style.rowPadding + 5);
    compare(row.spy.count, 2);
  }

  // Items under `item` (and in loaded ones) that satisfy `pred`
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

  // A number field builds only its mode's control: no stepper under the
  // slider, no slider under the stepper, the stepper as wide as before
  function test_number_field_builds_only_its_mode() {
    harness.configure({});
    const slider = createTemporaryObject(numberComp, root, {
      "width": 500,
      "mode": "slider"
    });
    waitForRendering(slider);
    compare(findAll(slider, it => it.autoRepeat !== undefined).length, 0);
    verify(findAll(slider, it => it.fillTone !== undefined).length > 0);
    const stepper = createTemporaryObject(numberComp, root, {
      "width": 500,
      "mode": "stepper"
    });
    waitForRendering(stepper);
    compare(findAll(stepper, it => it.fillTone !== undefined).length, 0);
    compare(findAll(stepper, it => it.autoRepeat !== undefined).length, 4 + (stepper.showCoarse ? 0 : -2));
    const box = findAll(stepper, it => it.tone === "sunken" && it.children.some(c => c.spacing === 2))[0];
    const row = box.children.find(c => c.spacing === 2);
    compare(box.implicitWidth, row.implicitWidth + stepper.containerMargins * 2);
    compare(box.implicitHeight, stepper.controlHeight);
  }

  // A row that does not act builds no hover layer and no click area
  function test_form_row_builds_its_hover_layer_only_while_hoverable() {
    harness.configure({});
    const row = createTemporaryObject(formRowComp, root);
    waitForRendering(row);
    compare(findAll(row, it => it.bleed !== undefined).length, 0);
    compare(findAll(row, it => it.cursorShape !== undefined).length, 0);
    row.hoverable = true;
    verify(findAll(row, it => it.bleed !== undefined).length > 0);
    verify(findAll(row, it => it.cursorShape !== undefined).length > 0);
    row.hoverable = false;
    compare(findAll(row, it => it.bleed !== undefined).length, 0);
  }

  // The More link is built only when the text is longer than its lines;
  // a click shows Less; the measurer counts the body's own lines
  function test_clamped_text_links_only_when_long() {
    harness.configure({});
    const short = createTemporaryObject(clampedComp, root, {
      "width": 400,
      "text": "Short"
    });
    waitForRendering(short);
    compare(short._long, false);
    compare(findAll(short, it => it.text === "More").length, 0);
    const long = createTemporaryObject(clampedComp, root, {
      "width": Widget.textPx(120),
      "text": "A much longer help text that wraps over many lines at this narrow width, well past two"
    });
    waitForRendering(long);
    compare(long._long, true);
    const body = long.children[0];
    verify(body.lineCount <= long.maxLines);
    const more = findAll(long, it => it.text === "More")[0];
    verify(more !== undefined);
    mouseClick(more, 1, 1);
    compare(long.expanded, true);
    verify(findAll(long, it => it.text === "Less").length > 0);
    compare(findAll(long, it => it.text === "More").length, 0);
    compare(body.lineCount, body.children[0].lineCount);
  }

  // A text button with no icon builds none; with one it is in the label's colour
  function test_button_builds_its_icon_only_with_one() {
    harness.configure({});
    const plain = createTemporaryObject(noIconButtonComp, root);
    waitForRendering(plain);
    compare(findAll(plain, it => it.isSymbol !== undefined).length, 0);
    const iconed = createTemporaryObject(buttonComp, root);
    waitForRendering(iconed);
    const icons = findAll(iconed, it => it.isSymbol !== undefined);
    compare(icons.length, 1);
    compare(String(icons[0].color), String(iconed._contentColor));
  }

  // A relay stops the walks of the texts in it and still answers for the
  // host and the zoom above it
  function test_relay_passes_ink_and_zoom_through() {
    harness.configure({});
    const host = createTemporaryObject(relayComp, root);
    waitForRendering(host);
    const text = host.loader.item;
    verify(text !== null);
    compare(String(text.color), String(Style.inkRaised.text));
    const zoomed = createTemporaryObject(zoomRelayComp, root);
    waitForRendering(zoomed);
    compare(zoomed.text.renderType, Text.QtRendering);
    zoomed.contentZoom = 1;
    compare(zoomed.text.renderType, Text.NativeRendering);
  }
}
