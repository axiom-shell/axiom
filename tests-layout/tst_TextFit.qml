import QtQuick
import QtTest
import qs.config
import qs.components.reusable

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

    StyledText {
    }
  }

  Component {
    id: menuRowComp

    MenuRow {
      icon: "folder"
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
