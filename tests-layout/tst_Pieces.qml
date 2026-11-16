import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.forms
import qs.components.methods
import qs.components.views.Settings

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

  // A row holding one control (`childComp`, given its size) in its body
  Component {
    id: hoverRowComp

    FormRow {
      id: hoverRow

      property Component childComp
      property alias holder: holder

      width: 300
      bodyHeight: 60

      Loader {
        id: holder

        x: 10
        y: 5
        sourceComponent: hoverRow.childComp
      }
    }
  }

  Component {
    id: hSwitchComp
    StyledSwitch {}
  }

  Component {
    id: hToggle2Comp
    StyledToggle {
      options: ["a", "b"]
      labels: ({
          "a": "A",
          "b": "B"
        })
      value: "a"
    }
  }

  Component {
    id: hToggle3Comp
    StyledToggle {
      options: ["a", "b", "c"]
      labels: ({
          "a": "A",
          "b": "B",
          "c": "C"
        })
      value: "a"
    }
  }

  Component {
    id: hSliderComp
    StyledSlider {
      width: 200
      height: 30
    }
  }

  Component {
    id: hComboComp
    StyledComboEntry {
      width: 200
      options: [
        {
          "value": "a",
          "label": "A"
        },
        {
          "value": "b",
          "label": "B"
        }
      ]
      value: "a"
    }
  }

  Component {
    id: hTextComp
    StyledTextEntry {
      width: 200
    }
  }

  Component {
    id: hMouseComp
    MouseArea {
      width: 100
      height: 30
      hoverEnabled: true
    }
  }

  Component {
    id: hClampedComp
    ClampedText {
      width: 150
      maxLines: 1
      text: "A much longer help text that wraps over many lines at this narrow width, well past one"
    }
  }

  Component {
    id: belowComp
    Item {
      property bool open: true
      readonly property bool shows: open
      implicitHeight: 40
    }
  }

  Component {
    id: toggleRowComp
    SchemaToggle {
      width: 600
      label: "A toggle"
      description: "What it does"
      options: ["a", "b"]
      optionLabels: ({
          "a": "A",
          "b": "B"
        })
      currentValue: "a"
    }
  }

  Component {
    id: threeToggleRowComp
    SchemaToggle {
      width: 600
      label: "A toggle"
      options: ["a", "b", "c"]
      optionLabels: ({
          "a": "A",
          "b": "B",
          "c": "C"
        })
      currentValue: "a"
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
    compare(row.height, Widget.height + Widget.padding, "a list row's height");
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
    // (in the strip's content, so it scrolls with its tab)
    const strip = bar.children.find(c => c.flickableDirection !== undefined);
    const underline = strip.contentItem.children.find(c => c.height === Widget.px(2) && c.visible);
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

  // A group is the settings page's card: surface-toned and outlined whatever
  // it sits on
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
      compare(host.group.tone, "surface", tone);
      compare(host.group.border.width, Style.hairline, tone);
    }
  }

  // A group with no title leaves no blank heading line
  function test_field_group_without_title_has_no_blank_heading() {
    harness.configure({});
    const titled = createTemporaryObject(groupComp, root, {
      "width": 400
    });
    const bare = createTemporaryObject(groupComp, root, {
      "width": 400,
      "title": ""
    });
    waitForRendering(titled);
    waitForRendering(bare);
    function titleItem(item) {
      if (item.role === "title")
        return item;
      for (const child of item.children) {
        const found = titleItem(child);
        if (found)
          return found;
      }
      return null;
    }
    const heading = titleItem(bare);
    verify(heading === null || heading.visible === false);
    verify(bare.implicitHeight < titled.implicitHeight);
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

  // A header with only a `below` part shows while the part does
  function test_field_header_shows_below_only_while_it_shows() {
    harness.configure({});
    const host = createTemporaryObject(headerComp, root, {
      "width": 300,
      "description": "",
      "below": belowComp
    });
    waitForRendering(host);
    verify(host.visible);
    verify(host.implicitHeight >= 40);
    const part = findAll(host, it => it.shows !== undefined)[0];
    part.open = false;
    verify(!host.visible);
    part.open = true;
    verify(host.visible);
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
    const control = findAll(toggle, c => c.options !== undefined && c.labels !== undefined)[0];
    const line = findAll(toggle, c => c.lineWidth !== undefined)[0].lineWidth;
    compare(toggle.stacked, !FieldFit.place("fixed", toggle.width, line, control.implicitWidth, Widget.fieldTokens).inline);
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
    // The tint band: the hit part of the body, padded below as above
    const layer = findAll(row, it => it.bleed !== undefined)[0];
    compare(layer.parent.parent.height, 20 + 2 * Style.rowPadding);
    mouseMove(row, 10, Style.rowPadding + 5);
    verify(row.hovered);
    mouseMove(row, 10, row.height - 2);
    verify(!row.hovered);
    mouseMove(root, 650, 450);
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

  // A stepper that wouldn't leave its label's line the room it needs goes
  // under the label (N12), the label keeping one line; the width is derived
  // from FieldFit, not hard-coded
  function test_number_field_stepper_stacks_under_a_narrow_label() {
    harness.configure({});
    const props = {
      "label": "Interval",
      "minimum": 500,
      "maximum": 86400000,
      "step": 500,
      "mode": "stepper"
    };
    const wide = createTemporaryObject(numberComp, root, Object.assign({
      "width": 700
    }, props));
    waitForRendering(wide);
    verify(wide.inline);
    const box = findAll(wide, it => it.tone === "sunken" && it.children.some(c => c.spacing === 2))[0];
    const line = findAll(wide, it => it.lineWidth !== undefined)[0].lineWidth;
    const tokens = Widget.fieldTokens;
    const narrowWidth = Math.ceil(box.implicitWidth + tokens.gap + Math.min(line, tokens.labelLeast)) - 1;
    const field = createTemporaryObject(numberComp, root, Object.assign({
      "width": narrowWidth
    }, props));
    waitForRendering(field);
    verify(!field.inline);
    const label = findAll(field, it => it.text === "Interval")[0];
    const stepper = findAll(field, it => it.tone === "sunken" && it.children.some(c => c.spacing === 2))[0];
    verify(stepper.mapToItem(field, 0, 0).y >= label.mapToItem(field, 0, label.height).y);
    verify(label.height < label.font.pixelSize * 2);
  }

  // A row tints unless `tinted` is off; its click area shows only while hoverable
  function test_form_row_tints_unless_untinted() {
    harness.configure({});
    const row = createTemporaryObject(formRowComp, root);
    waitForRendering(row);
    verify(findAll(row, it => it.bleed !== undefined).length > 0);
    compare(findAll(row, it => it.cursorShape !== undefined && it.visible).length, 0);
    row.hoverable = true;
    verify(findAll(row, it => it.cursorShape !== undefined && it.visible).length > 0);
    row.hoverable = false;
    compare(findAll(row, it => it.cursorShape !== undefined && it.visible).length, 0);
    row.tinted = false;
    compare(findAll(row, it => it.bleed !== undefined).length, 0);
    row.hoverable = true;
    verify(findAll(row, it => it.bleed !== undefined).length > 0);
  }

  function test_form_row_keeps_hover_over_its_controls_data() {
    const out = [];
    for (const [name, comp] of [["switch", hSwitchComp], ["toggle2", hToggle2Comp], ["toggle3", hToggle3Comp], ["slider", hSliderComp], ["combo", hComboComp], ["text", hTextComp], ["mouse", hMouseComp], ["more", hClampedComp]])
      for (const hoverable of [false, true])
        out.push({
          "tag": `${name} ${hoverable ? "hoverable" : "plain"}`,
          "comp": comp,
          "name": name,
          "hoverable": hoverable
        });
    return out;
  }

  // The pointer over any control of the row keeps the row's hover (the
  // handler is on the row, an ancestor of every control)
  function test_form_row_keeps_hover_over_its_controls(data) {
    harness.configure({});
    const row = createTemporaryObject(hoverRowComp, root, {
      "childComp": data.comp,
      "hoverable": data.hoverable
    });
    waitForRendering(row);
    let target = row.holder.item;
    if (data.name === "more") {
      target = findAll(row, it => it.text === "More")[0];
      verify(target !== undefined, "the More link");
    }
    mouseMove(root, 650, 450);
    verify(!row.hovered);
    mouseMove(target, target.width / 2, target.height / 2);
    wait(50);
    verify(row.hovered, `${data.tag}: row hovered over the control`);
    const layer = findAll(row, it => it.bleed !== undefined)[0];
    verify(layer.hovered, `${data.tag}: the tint shows`);
    mouseMove(root, 650, 450);
    verify(!row.hovered);
  }

  function test_toggle_click_picks_the_segment_data() {
    return [
      {
        "tag": "two",
        "comp": hToggle2Comp,
        "values": ["a", "b"]
      },
      {
        "tag": "three",
        "comp": hToggle3Comp,
        "values": ["a", "b", "c"]
      }
    ];
  }

  // A click on a segment picks it; on the chosen one, nothing
  function test_toggle_click_picks_the_segment(data) {
    harness.configure({});
    const toggle = createTemporaryObject(data.comp, root);
    waitForRendering(toggle);
    const spy = createTemporaryObject(pickSpyComp, root, {
      "target": toggle
    });
    mouseClick(toggle, toggle._inset + toggle._segment * 0.5, toggle.height / 2);
    compare(spy.count, 0);
    for (let i = 1; i < data.values.length; i++) {
      mouseClick(toggle, toggle._inset + toggle._segment * (i + 0.5), toggle.height / 2);
      compare(spy.count, i);
      compare(spy.signalArguments[i - 1][0], data.values[i]);
    }
  }

  Component {
    id: pickSpyComp
    SignalSpy {
      signalName: "picked"
    }
  }

  function test_schema_toggle_row_click_cycles_data() {
    return [
      {
        "tag": "two",
        "comp": toggleRowComp,
        "values": ["a", "b"]
      },
      {
        "tag": "three",
        "comp": threeToggleRowComp,
        "values": ["a", "b", "c"]
      }
    ];
  }

  function test_schema_toggle_row_click_cycles(data) {
    harness.configure({});
    const toggle = createTemporaryObject(data.comp, root);
    waitForRendering(toggle);
    const spy = createTemporaryObject(pickSpyComp, root, {
      "target": toggle
    });
    for (let i = 0; i < data.values.length; i++) {
      toggle.currentValue = data.values[i];
      toggle.activate();
      compare(spy.signalArguments[i][0], data.values[(i + 1) % data.values.length]);
    }
  }

  // A hoverable row around a toggle, wired as SchemaField wires it (the real
  // SchemaField needs SettingsManager, which the layout harness has no
  // stub for, so its tinted/hoverable predicates stay untested here)
  Component {
    id: toggleInRowComp
    FormRow {
      id: wrapper
      property alias toggle: inner
      width: 600
      bodyHeight: inner.implicitHeight
      hoverable: true
      onRowClicked: inner.activate()
      SchemaToggle {
        id: inner
        width: parent.width
        label: "A toggle"
        description: "What it does"
        options: ["a", "b", "c"]
        optionLabels: ({
            "a": "A",
            "b": "B",
            "c": "C"
          })
        currentValue: "a"
      }
    }
  }

  // A click on the row's background (off the toggle) cycles it
  function test_form_row_background_click_cycles_its_toggle() {
    harness.configure({});
    const row = createTemporaryObject(toggleInRowComp, root);
    waitForRendering(row);
    const spy = createTemporaryObject(pickSpyComp, root, {
      "target": row.toggle
    });
    mouseClick(row, 1, row.height / 2);
    compare(spy.count, 1);
    compare(spy.signalArguments[0][0], "b");
  }

  function test_trailing_control_centres_on_the_label_block_data() {
    return [
      {
        "tag": "combo",
        "kind": "listOpen",
        "comp": comboRowComp
      },
      {
        "tag": "switch",
        "kind": "compact",
        "comp": switchRowComp
      },
      {
        "tag": "toggle",
        "kind": "_segment",
        "comp": toggleRowComp
      },
      {
        "tag": "slider",
        "kind": "fillTone",
        "comp": sliderRowComp
      }
    ];
  }

  Component {
    id: comboRowComp
    SchemaComboBox {
      width: Widget.fieldInlineFrom + 200
      label: "A choice"
      description: "What it does"
      options: ["a", "b"]
      currentValue: "a"
    }
  }

  Component {
    id: switchRowComp
    SchemaSwitch {
      width: 600
      label: "A switch"
      description: "What it does"
      checked: false
    }
  }

  Component {
    id: sliderRowComp
    SchemaNumberField {
      width: Widget.fieldInlineFrom + 200
      label: "A slider"
      description: "What it does"
      mode: "slider"
      minimum: 0
      maximum: 100
      currentConfigValue: 50
    }
  }

  // The control sits on the middle of title, description and the line
  // under them; a part that doesn't show adds nothing
  function test_trailing_control_centres_on_the_label_block(data) {
    harness.configure({});
    const field = createTemporaryObject(data.comp, root, {
      "headerBelow": belowComp
    });
    waitForRendering(field);
    // The label's line and the notes (description, links) are two headers
    const heads = findAll(field, it => it.below !== undefined && it.trailing !== undefined);
    const header = heads[0];
    const notes = heads[1];
    const part = findAll(notes, it => it.shows !== undefined)[0];
    const top = header.mapToItem(field, 0, 0).y;
    const bottom = () => notes.mapToItem(field, 0, notes.height).y;
    verify(part !== undefined && bottom() - top >= 40 + Widget.spacing / 2);
    const middle = item => item.mapToItem(field, 0, item.height / 2).y;
    const control = findAll(field, it => it[data.kind] !== undefined)[0];
    verify(control !== undefined, "a trailing control");
    verify(Math.abs(middle(control) - (top + bottom()) / 2) <= 1, `${data.tag}: control ${middle(control)} block ${(top + bottom()) / 2}`);
    const tall = bottom() - top;
    part.open = false;
    tryVerify(() => bottom() - top < tall - 40 + 1);
  }

  // Stacked (a narrow row), the links sit above the control, never beside it
  function test_stacked_toggle_keeps_its_link_above() {
    harness.configure({});
    const field = createTemporaryObject(toggleRowComp, root, {
      "width": Widget.textPx(120),
      "headerBelow": belowComp
    });
    waitForRendering(field);
    verify(field.stacked);
    const notes = findAll(field, it => it.below !== undefined && it.trailing !== undefined)[1];
    const control = findAll(field, it => it._segment !== undefined)[0];
    const top = control.mapToItem(field, 0, 0).y;
    verify(notes.mapToItem(field, 0, notes.height).y <= top, "the notes, link included, end above the toggle");
  }

  // On a narrow line that fits, the toggle sits at the right end, centred on
  // the label, description and links, which sit under the label to its left
  function test_narrow_inline_toggle_keeps_its_link_beside() {
    harness.configure({});
    const field = createTemporaryObject(toggleRowComp, root, {
      "width": Widget.textPx(300),
      "headerBelow": belowComp
    });
    waitForRendering(field);
    verify(!field.stacked);
    const heads = findAll(field, it => it.below !== undefined && it.trailing !== undefined);
    const header = heads[0];
    const notes = heads[1];
    const control = findAll(field, it => it._segment !== undefined)[0];
    verify(notes.mapToItem(field, notes.width, 0).x <= control.mapToItem(field, 0, 0).x + 1, "the notes sit left of the toggle");
    verify(notes.mapToItem(field, 0, 0).y >= header.mapToItem(field, 0, header.height).y - 1, "the notes sit under the label");
    verify(Math.abs(control.mapToItem(field, 0, control.height / 2).y - field.height / 2) <= 1, "the toggle is centred on the whole box");
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

  // The underline heads straight for its final place: no overshoot, no creep back
  function test_tab_bar_underline_slides_without_overshoot() {
    harness.configure({});
    const bar = createTemporaryObject(tabBarComp, root, {
      "tabs": ["A", "A much longer label", "B"],
      "currentIndex": 0,
      "width": Widget.textPx(330)
    });
    waitForRendering(bar);
    tryVerify(() => bar._settled);
    const mark = findAll(bar, it => it.height === Widget.px(2) && it.radius !== undefined && it.visible)[0];
    verify(mark !== undefined, "the underline shows");
    bar.currentIndex = 1;
    const tab = bar._current;
    const width = bar._markWidth;
    const left = tab.x + (tab.width - width) / 2;
    const right = left + width;
    let prevLeft = mark.x;
    let settledAt = -1;
    const start = Date.now();
    for (let i = 0; i < 60; i++) {
      wait(5);
      verify(mark.x <= left + 0.5, "left edge past its place: " + mark.x + " > " + left);
      verify(mark.x + mark.width <= right + 0.5, "right edge past its place: " + (mark.x + mark.width) + " > " + right);
      verify(mark.x >= prevLeft - 0.5, "left edge moved back: " + prevLeft + " -> " + mark.x);
      prevLeft = mark.x;
      if (settledAt < 0 && Math.abs(mark.x - left) < 0.5 && Math.abs(mark.width - width) < 0.5)
        settledAt = Date.now() - start;
    }
    // one move of animNormal, not a chase that trails behind it
    verify(settledAt >= 0 && settledAt <= Appearance.animNormal + 60, "settled after " + settledAt + " ms");
    tryVerify(() => Math.abs(mark.x - left) < 0.5 && Math.abs(mark.width - width) < 0.5);
  }

  Component {
    id: streamedComp
    StreamedLoader {
      always: true
      sourceComponent: Rectangle {
        implicitWidth: 20
        implicitHeight: 20
      }
    }
  }

  // `rise: false` only fades: the slide's distance stays 0 as the item arrives
  function test_streamed_loader_rise_opt_out() {
    harness.configure({});
    const rising = createTemporaryObject(streamedComp, root);
    verify(rising.item !== null, "built");
    compare(rising._enter, Style.enterOffset);
    const fading = createTemporaryObject(streamedComp, root, {
      "rise": false
    });
    verify(fading.item !== null, "built");
    compare(fading._enter, 0);
    compare(fading.transform.length, 0);
  }

  // A loader that only fades makes no slide (no Translate), and shows its item at once
  function test_streamed_loader_fade_only_builds_no_slide() {
    harness.configure({});
    const fading = createTemporaryObject(streamedComp, root, {
      "rise": false
    });
    verify(fading.item !== null, "built");
    compare(fading.transform.length, 0);
    verify(fading._entered, "shown");
    const rising = createTemporaryObject(streamedComp, root);
    compare(rising.transform.length, 1);
  }

  Component {
    id: switchComp

    StyledSwitch {}
  }

  function test_switch_knob_follows_its_track_data() {
    return [
      {
        "tag": "100",
        "scale": 100
      },
      {
        "tag": "150",
        "scale": 150
      }
    ];
  }

  // The knob's corners are concentric in the track, whatever the track's radius
  function test_switch_knob_follows_its_track(data) {
    harness.configure({
      "scale": data.scale
    });
    const sw = createTemporaryObject(switchComp, root);
    waitForRendering(sw);
    compare(sw.indicator.radius, StyleTokens.concentric(sw.background.radius, Widget.px(2), Style.radiusMin));
    sw.background.radius = Widget.px(5);
    compare(sw.indicator.radius, StyleTokens.concentric(Widget.px(5), Widget.px(2), Style.radiusMin));
  }

  // The stepper's buttons have corners concentric in their box
  function test_stepper_buttons_are_concentric_in_their_box() {
    harness.configure({});
    const stepper = createTemporaryObject(numberComp, root, {
      "width": 500,
      "mode": "stepper"
    });
    waitForRendering(stepper);
    const box = findAll(stepper, it => it.tone === "sunken" && it.children.some(c => c.spacing === 2))[0];
    const buttons = findAll(stepper, it => it.autoRepeat !== undefined && it.visible);
    verify(buttons.length >= 2, "the stepper shows its buttons");
    for (const b of buttons) {
      compare(b.borderRadius, StyleTokens.concentric(box.radius, stepper.containerMargins, Style.radiusMin));
      verify(b.borderRadius < box.radius, "inner corners tighter than the box's");
    }
  }

  // The switch track is the toggle's shape (the switch-shape FLAG)
  function test_switch_takes_the_toggle_shape() {
    harness.configure({});
    const sw = createTemporaryObject(switchComp, root);
    waitForRendering(sw);
    compare(sw.background.radius, Style.radiusInner);
    compare(sw.indicator.radius, StyleTokens.concentric(Style.radiusInner, Widget.px(2), Style.radiusMin));
  }

  Component {
    id: stateComp

    Rectangle {
      width: 100
      height: 40
      radius: 6

      StateLayer {
        objectName: "layer"
      }
    }
  }

  Component {
    id: ringComp

    Rectangle {
      width: 100
      height: 40
      radius: 6

      FocusRing {
        objectName: "ring"
      }
    }
  }

  Component {
    id: skeletonComp

    Skeleton {
      width: 300
    }
  }

  Component {
    id: trackComp

    SegmentTrack {
      width: 300
      height: 40
      count: 3
    }
  }

  Component {
    id: motionComp

    MotionListView {
      width: 100
      height: 100
      model: 3
      delegate: Item {
        required property int index

        width: 100
        height: 20
      }
    }
  }

  // The state tint: rest, hover, press (over hover), drag and the on-accent set
  function test_state_layer_tints_by_state() {
    harness.configure({});
    const host = createTemporaryObject(stateComp, root);
    const layer = host.children[0];
    compare(layer.width, host.width);
    tryCompare(layer, "color", Style.stateRest);
    layer.hovered = true;
    layer.pressed = true;
    tryCompare(layer, "color", Style.statePressed);
    layer.pressed = false;
    layer.dragged = true;
    tryCompare(layer, "color", Style.stateDrag);
    layer.dragged = false;
    tryCompare(layer, "color", Style.stateHover);
    layer.onAccent = true;
    tryCompare(layer, "color", Style.stateOnAccentHover);
    layer.hovered = false;
    tryCompare(layer, "color", Style.stateOnAccentRest);
    layer.bleed = 4;
    compare(layer.width, host.width + 8);
  }

  // The ring shows only with `shown`, sits outside its parent and follows its radius
  function test_focus_ring_follows_its_parent() {
    harness.configure({});
    const host = createTemporaryObject(ringComp, root);
    const ring = host.children[0];
    compare(ring.visible, false);
    ring.shown = true;
    compare(ring.visible, true);
    compare(ring.radius, host.radius + Style.focusWidth);
    compare(ring.width, host.width + Style.focusWidth * 2);
    compare(ring.x, -Style.focusWidth);
    host.radius = 10;
    compare(ring.radius, 10 + Style.focusWidth);
  }

  // The skeleton makes one bar per line, the last shorter, and an avatar on request
  function test_skeleton_bars_and_avatar() {
    harness.configure({});
    const sk = createTemporaryObject(skeletonComp, root, {
      "lines": 3
    });
    waitForRendering(sk);
    const bars = findAll(sk, it => it.last !== undefined && it.height === sk._bar);
    compare(bars.length, 3);
    const widths = bars.slice(0, 3).map(b => b.width);
    verify(widths[2] < widths[0], "the last bar is shorter: " + widths);
    const one = createTemporaryObject(skeletonComp, root, {
      "lines": 1
    });
    waitForRendering(one);
    const only = findAll(one, it => it.last !== undefined && it.height === one._bar);
    verify(only.length > 0 && Math.abs(only[0].width - one.width) < 1, "a single line spans the width");
    const discs = it => findAll(it, c => c.radius !== undefined && c.width === Style.iconLg && c.height === Style.iconLg && c.visible);
    compare(discs(one).length, 0);
    one.avatar = true;
    waitForRendering(one);
    compare(discs(one).length, 1);
  }

  // The thumb sits under segment `index`, as wide as a segment, with corners concentric in the track
  function test_segment_track_thumb_follows_index() {
    harness.configure({});
    const track = createTemporaryObject(trackComp, root);
    waitForRendering(track);
    const thumb = findAll(track, it => it.tone === Style.segmentThumbTone && it !== track)[0];
    verify(thumb !== undefined, "has a thumb");
    compare(thumb.width, Math.round(track._segment));
    tryCompare(thumb, "x", Math.round(track.inset));
    track.index = 2;
    tryCompare(thumb, "x", Math.round(track.inset + 2 * track._segment));
    compare(thumb.radius, StyleTokens.concentric(track.radius, track.inset, Style.radiusMin));
    compare(thumb.height, track.height - track.inset * 2);
    track.count = 0;
    verify(track._segment > 0 && isFinite(track._segment), "an empty track does not divide by zero");
  }

  // The first model fill never animates unless asked; later changes do (with the shell's animations)
  function test_motion_list_view_skips_first_fill() {
    harness.configure({});
    const view = createTemporaryObject(motionComp, root);
    compare(view._settled, false);
    compare(view._animate, false);
    tryCompare(view, "_settled", true);
    compare(view._animate, Appearance.animations);
    const first = createTemporaryObject(motionComp, root, {
      "animateFirstFill": true
    });
    compare(first._animate, Appearance.animations);
  }

  // A StateLayer rounds as its parent; with none to follow it takes the inner radius
  function test_state_layer_radius() {
    harness.configure({});
    const rect = createTemporaryObject(stateLayerComp, root, {
      "radius": 13
    });
    compare(findAll(rect, it => it.objectName === "layer")[0].radius, 13);
    const plain = createTemporaryObject(plainLayerComp, root);
    compare(findAll(plain, it => it.objectName === "layer")[0].radius, Style.radiusInner);
    const chip = createTemporaryObject(toggleChipComp, root);
    const layer = findAll(chip, it => it.hovered !== undefined && it.onAccent !== undefined && it.parent === chip)[0];
    verify(layer !== undefined, "the chip's StateLayer");
    compare(layer.radius, chip.height / 2);
  }

  Component {
    id: stateLayerComp

    Rectangle {
      width: 40
      height: 40

      StateLayer {
        objectName: "layer"
      }
    }
  }

  Component {
    id: plainLayerComp

    Item {
      width: 40
      height: 40

      StateLayer {
        objectName: "layer"
      }
    }
  }

  Component {
    id: toggleChipComp

    ToggleChip {
      text: "chip"
    }
  }

  function test_segment_row_matches_toggle_height() {
    harness.configure({});
    const row = createTemporaryObject(segmentComp, root, {
      "labels": ["a", "b"]
    });
    const toggle = createTemporaryObject(toggleComp, root);
    row.width = Math.max(row.implicitWidth, 200);
    waitForRendering(row);
    compare(row.height, toggle.height);
  }

  // A scrollable tab bar's focus ring stays inside the strip for the first and last tab
  function test_scrollable_tab_ring_inside_strip() {
    harness.configure({});
    const bar = createTemporaryObject(tabBarComp, root, {
      "width": Widget.textPx(160),
      "scrollable": true
    });
    waitForRendering(bar);
    const strip = bar.children.find(c => c.flickableDirection !== undefined);
    for (const index of [0, 2]) {
      bar.currentIndex = index;
      waitForRendering(bar);
      tryVerify(() => strip.contentX >= 0);
      const tabs = findAll(strip.contentItem, it => it.checked !== undefined && it.text !== undefined);
      const tab = tabs.find(t => t.text === ["First", "Second", "Third"][index]);
      verify(tab !== undefined);
      const ring = findAll(tab, it => it.shown !== undefined && it._host !== undefined)[0];
      verify(ring !== undefined, "the tab's FocusRing");
      ring.shown = true;
      const tl = ring.mapToItem(strip, 0, 0);
      verify(tl.x >= 0 && tl.y >= 0, `tab ${index} ring starts inside: ${tl.x},${tl.y}`);
      verify(tl.x + ring.width <= strip.width + 0.5, `tab ${index} ring ends inside (${tl.x + ring.width} of ${strip.width})`);
      verify(tl.y + ring.height <= strip.height + 0.5, `tab ${index} ring is inside vertically`);
    }
  }

  function test_fold_chevron_rotation() {
    const chev = createTemporaryObject(foldChevronComp, root);
    chev.open = true;
    tryCompare(chev, "rotation", 0);
    chev.open = false;
    tryCompare(chev, "rotation", -90);
  }

  Component {
    id: foldChevronComp

    FoldChevron {}
  }

  Component {
    id: entryTabsComp

    EntryTabs {
      count: 3
      labelAt: i => ["first", "second", "third"][i]
    }
  }

  // The entry tabs are default-height segment buttons (not shortened) showing their label whole
  function test_entry_tabs_default_height() {
    const tabs = createTemporaryObject(entryTabsComp, root, {
      "width": 400
    });
    waitForRendering(tabs);
    const buttons = Array.prototype.filter.call(tabs.children, c => c instanceof SegmentButton);
    compare(buttons.length, 3);
    // the button's own height (no -4 override): at least a field's, all alike
    for (const b of buttons) {
      verify(b.height >= Widget.height, `tab ${b.text} is ${b.height}, under ${Widget.height}`);
      compare(b.height, buttons[0].height);
    }
    for (const t of harness.texts(tabs))
      verify(!t.truncated, `"${t.text}" is elided`);
  }

  // A foldable header is a Tab stop: Tab focuses it, Space and Enter fold it; a fixed one is not
  function test_fold_header_keyboard() {
    const head = createTemporaryObject(foldHeaderComp, root);
    const folds = [];
    head.toggled.connect(() => folds.push(1));
    verify(head.activeFocusOnTab);
    keyClick(Qt.Key_Tab);
    verify(head.activeFocus, "Tab focuses the header");
    keyClick(Qt.Key_Space);
    keyClick(Qt.Key_Return);
    compare(folds.length, 2);
    const fixed = createTemporaryObject(foldHeaderComp, root, {
      "foldable": false
    });
    compare(fixed.activeFocusOnTab, false);
  }

  // Style holds each role as its derivation made it: a property named on<X>
  // beside <x> never takes its value (qml-pitfalls.md), reading black
  function test_styleColoursMatchRoles() {
    harness.configure({
      theme: "rose-pine"
    });
    const bad = [];
    for (const k of Object.keys(Style._roles)) {
      const v = String(Style._roles[k]);
      if (Style[k] === undefined || !/^#[0-9a-fA-F]{6,8}$/.test(v))
        continue;
      if (String(Style[k]) !== v)
        bad.push(k + ": " + String(Style[k]) + " vs " + v);
    }
    compare(bad.join(", "), "");
    harness.configure({});
  }

  Component {
    id: volumeBarComp

    StyledVolumeBar {
      isMuted: true
      showPercent: true
      volumeLevel: 0.5
    }
  }

  // The muted highlight is a step lighter than the card, over the whole bar
  function test_volumeBarMuted() {
    harness.configure({
      theme: "rose-pine"
    });
    for (const o of [Qt.Vertical, Qt.Horizontal]) {
      const bar = createTemporaryObject(volumeBarComp, root, {
        orientation: o
      });
      verify(bar);
      wait(Appearance.animNormal + 200);
      const bg = bar.children.find(c => c.tone === "highest");
      verify(bg, "a highest-tone background");
      compare(String(bg.color), String(Style.fillHighest));
      compare(bg.width, bar.width);
      compare(bg.height, bar.height);
      if (o === Qt.Horizontal)
        compare(bar.implicitWidth, Widget.px(160));
      compare(bar.implicitHeight, Widget.px(o === Qt.Vertical ? 160 : 48));
    }
    harness.configure({});
  }

  // The knob is the foreground in dark and light themes alike
  function test_sliderKnob_data() {
    return [
      {
        tag: "dark",
        theme: "catppuccin-mocha"
      },
      {
        tag: "light",
        theme: "catppuccin-latte"
      }
    ];
  }

  function test_sliderKnob(data) {
    harness.configure({
      theme: data.theme
    });
    const slider = createTemporaryObject(hSliderComp, root);
    verify(slider);
    compare(String(slider.handleColor), String(Style.text));
    harness.configure({});
  }

  Component {
    id: pinnedListComp

    PinnedList {
      id: list
      property int count: 2
      width: 300
      maxHeight: 100

      Repeater {
        model: list.count
        Rectangle {
          required property int index
          Layout.fillWidth: true
          implicitHeight: 30
          color: "transparent"
        }
      }
    }
  }

  // A list taller than its cap scrolls inside it (cut, with a scroll bar); a short one takes its own height
  function test_pinnedList() {
    const tall = createTemporaryObject(pinnedListComp, root, {
      "count": 20
    });
    verify(tall);
    waitForRendering(tall);
    wait(30);
    compare(tall.height, 100);
    compare(tall.cut, true);
    compare(findAll(tall, it => it.showScrollBar === true).length, 1, "a scroll bar");
    const short = createTemporaryObject(pinnedListComp, root, {
      "count": 2
    });
    waitForRendering(short);
    wait(30);
    compare(short.height, short.contentHeight);
    compare(short.cut, false);
    compare(findAll(short, it => it.showScrollBar === true).length, 0, "no scroll bar");
  }
}
