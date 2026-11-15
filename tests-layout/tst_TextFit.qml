import QtQuick
import QtQuick.Layouts
import QtTest
import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Text fit at every scale, font size, density and width (the layout harness,
// scripts/qml_modules.py --layout): a piece holds its texts, a one-line text
// has one line, a wrapping one is capped, a long unbroken token never leaves
// its box; StyledText is native at rest and distance field under a zoom.
TestCase {
  id: root

  name: "TextFit"
  when: windowShown
  visible: true
  width: 600
  height: 400

  Harness {
    id: harness
  }

  FontMetrics {
    id: fontMetrics

    font.family: Appearance.fontFamily
    font.pixelSize: 14
  }

  Component {
    id: textComp

    StyledText {}
  }

  Component {
    id: menuRowComp

    MenuRow {
      icon: "folder"
    }
  }

  Component {
    id: moduleHeaderComp

    ModuleHeader {
      icon: "hard_drive"
    }
  }

  Component {
    id: moduleHeaderTrailComp

    ModuleHeader {
      readonly property Item button: trailButton
      icon: "wallpaper"

      StyledText {
        Layout.maximumWidth: Widget.textPx(160)
        overflow: "line"
        text: "Generating themes for every wallpaper in the folder"
      }
      StyledIconButton {
        id: trailButton
        iconText: "skip_next"
      }
    }
  }

  Component {
    id: cardHeaderComp

    CardHeader {}
  }

  Component {
    id: emptyStateComp

    EmptyState {
      icon: "inbox"
    }
  }

  Component {
    id: zoomComp

    Item {
      property real contentZoom: 0.9
      property alias text: inner

      StyledText {
        id: inner

        text: "zoomed"
      }
    }
  }

  readonly property var strings: ({
      "en": "Open the settings file",
      "ja": "設定ファイルを開く",
      "enLong": "Open the settings file in the default editor for the current project",
      "token": "a".repeat(40)
    })

  // The first test of the file fails loudly on a runner without the font,
  // instead of every row passing vacuously
  function test_00_font_is_present() {
    harness.configure({});
    verify(fontMetrics.advanceWidth("W") > 0);
    compare(Appearance.fontFamily, "DejaVu Sans Mono");
  }

  function rows() {
    const out = [];
    for (const scale of [75, 100, 150])
      for (const fontSize of [8, 14, 32])
        for (const density of ["compact", "roomy"])
          for (const width of ["narrow", "wide"])
            for (const key of ["en", "ja", "enLong", "token"])
              out.push({
                "tag": `${scale}% font ${fontSize} ${density} ${width} ${key}`,
                "scale": scale,
                "fontSize": fontSize,
                "density": density,
                "width": width,
                "key": key
              });
    return out;
  }

  function test_menu_row_holds_its_text_data() {
    return rows();
  }

  function test_menu_row_holds_its_text(data) {
    harness.configure(data);
    // the row's fixed parts (padding, icon, trailing detail) and then a measure of text
    const fixed = Widget.padding * 2 + Style.iconMd + Widget.spacing * 2 + Widget.textPx(60);
    const row = createTemporaryObject(menuRowComp, root, {
      "text": strings[data.key],
      "trailing": "Ctrl+O",
      "width": fixed + (data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400))
    });
    waitForRendering(row);
    compare(harness.containedProblems(row), []);
    verify(row.implicitHeight >= Math.ceil(1.5 * Appearance.fontSize), "the row holds a line of its font");
    for (const t of harness.texts(row)) {
      if (t.text === row.text)
        compare(t.lineCount, 1);
    }
  }

  // A module's header: the title elides in its row before the trailing items
  function test_module_header_holds_its_title_data() {
    return rows();
  }

  function test_module_header_holds_its_title(data) {
    harness.configure(data);
    const header = createTemporaryObject(moduleHeaderComp, root, {
      "title": strings[data.key],
      "width": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    waitForRendering(header);
    compare(harness.containedProblems(header), []);
    for (const t of harness.texts(header)) {
      if (t.text === header.title)
        compare(t.lineCount, 1);
    }
  }

  function test_module_header_keeps_trailing_items_inside_data() {
    return rows();
  }

  function test_module_header_keeps_trailing_items_inside(data) {
    harness.configure(data);
    const header = createTemporaryObject(moduleHeaderTrailComp, root, {
      "title": strings[data.key],
      "width": Widget.textPx(400)
    });
    waitForRendering(header);
    // the harness has no icon font, so the glyph's name paints as wide text: judge the label, the button's box below
    compare(harness.containedProblems(header).filter(p => !p.startsWith('"skip_next"')), []);
    compare(header.button.width, header.button.size);
    const at = header.button.mapToItem(header, 0, 0);
    verify(at.x + header.button.width <= header.width + 0.5);
  }

  // A panel's header: one line of title, with the Save and Discard buttons
  function test_card_header_holds_its_title_data() {
    return rows();
  }

  function test_card_header_holds_its_title(data) {
    harness.configure(data);
    const header = createTemporaryObject(cardHeaderComp, root, {
      "title": strings[data.key],
      "dirty": true,
      "height": Widget.height * 2,
      // never under what its two icon buttons need (the narrowest a panel is)
      "width": Math.max(data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400), Widget.height * 4 + Widget.spacing * 3)
    });
    waitForRendering(header);
    compare(harness.containedProblems(header), []);
    for (const t of harness.texts(header)) {
      if (t.text === header.title)
        compare(t.lineCount, 1);
    }
  }

  // An empty state: its text and hint wrap inside `maxWidth`
  function test_empty_state_holds_its_text_data() {
    return rows();
  }

  function test_empty_state_holds_its_text(data) {
    harness.configure(data);
    const state = createTemporaryObject(emptyStateComp, root, {
      "text": strings[data.key],
      "hint": strings[data.key],
      "maxWidth": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    waitForRendering(state);
    compare(harness.containedProblems(state), []);
  }

  // An empty state given less room than its full height shows only the icon;
  // given its full height it keeps the text, hint and button
  function test_empty_state_keeps_to_its_room_data() {
    return rows();
  }

  function test_empty_state_keeps_to_its_room(data) {
    harness.configure(data);
    const state = createTemporaryObject(emptyStateComp, root, {
      "text": strings[data.key],
      "hint": strings[data.key],
      "actionText": "Retry",
      "maxWidth": Widget.textPx(400)
    });
    waitForRendering(state);
    const full = state.implicitHeight;
    state.availableHeight = full - 1;
    waitForRendering(state, 1000);
    verify(state.implicitHeight <= state.availableHeight + 0.5, `${state.implicitHeight} in ${state.availableHeight}`);
    state.availableHeight = full;
    waitForRendering(state, 1000);
    compare(state.implicitHeight, full);
  }

  function test_roles_hold_their_text_data() {
    const out = [];
    for (const row of rows())
      for (const role of ["micro", "caption", "body", "label", "title", "headline", "display"])
        out.push(Object.assign({}, row, {
          "role": role,
          "tag": `${role} ${row.tag}`
        }));
    return out.filter((_, i) => i % 7 === 0);
  }

  function test_roles_hold_their_text(data) {
    harness.configure(data);
    const box = createTemporaryObject(boxComp, root, {
      "width": data.width === "narrow" ? Widget.textPx(140) : Widget.textPx(400)
    });
    // a text with a bound (a fillWidth in a layout) in its box; a `none` text (a figure) is sized by its box
    const text = textComp.createObject(box, {
      "role": data.role,
      "text": strings[data.key],
      "maxLines": 3,
      "width": box.width
    });
    waitForRendering(box);
    const overflow = text.overflow || text._role.overflow;
    if (overflow !== "none")
      compare(harness.containedProblems(box), []);
    if (overflow === "line")
      compare(text.lineCount, 1);
    else if (overflow === "wrap")
      verify(text.lineCount <= 3);
  }

  Component {
    id: boxComp

    Item {
      height: 400
    }
  }

  // Native outside a zoom host, distance field inside one
  function test_render_type() {
    harness.configure({});
    const plain = createTemporaryObject(textComp, root, {
      "text": "plain"
    });
    compare(plain.renderType, Text.NativeRendering);
    const zoomed = createTemporaryObject(zoomComp, root);
    compare(zoomed.text.renderType, Text.QtRendering);
    zoomed.contentZoom = 1;
    compare(zoomed.text.renderType, Text.NativeRendering);
  }
}
