import QtQuick
import QtTest
import qs.config
import qs.components.reusable
import qs.components.methods

// The five trough pieces draw one trough: Style.trough (= surfaceHighest),
// plain with no outline, the rounded ends kept; a muted volume bar's trough
// steps toward the text so it reads on its highest highlight.
TestCase {
  id: root

  name: "Meters"
  when: windowShown
  visible: true
  width: 400
  height: 300

  Harness {
    id: harness
  }

  Component {
    id: sliderComp
    StyledSlider {
      width: 200
    }
  }
  Component {
    id: levelComp
    LevelMeter {
      width: 200
      height: 20
    }
  }
  Component {
    id: segmentComp
    SegmentMeter {
      width: 200
      height: 20
    }
  }
  Component {
    id: ringComp
    PercentageCircle {}
  }
  Component {
    id: barComp
    StyledVolumeBar {}
  }

  function test_trough_is_one_role() {
    verify(Qt.colorEqual(Style.trough, Style.surfaceHighest));
    const slider = createTemporaryObject(sliderComp, root);
    const level = createTemporaryObject(levelComp, root);
    const segments = createTemporaryObject(segmentComp, root);
    const ring = createTemporaryObject(ringComp, root);
    const bar = createTemporaryObject(barComp, root);
    verify(slider && level && segments && ring && bar);
    verify(Qt.colorEqual(slider.troughColor, Style.trough));
    verify(Qt.colorEqual(level.trackColor, Style.trough));
    verify(Qt.colorEqual(segments.offColor, Style.trough));
    verify(Qt.colorEqual(ring.trackColor, Style.trough));
    const trough = findChild(bar, "trough");
    verify(trough);
    verify(Qt.colorEqual(trough.color, Style.trough));
    compare(trough.border.width, 0);
    // A Rectangle's border reads 1 unless it is set, so each piece sets 0
    compare(findChild(slider, "trough").border.width, 0);
    compare(findChild(level, "trough").border.width, 0);
    compare(trough.radius, Style.radius);
  }

  function test_no_outline() {
    for (const comp of [sliderComp, levelComp, segmentComp, ringComp, barComp]) {
      const item = createTemporaryObject(comp, root);
      verify(item);
      // hasOwnProperty passes vacuously for a QML-declared property; reading it does not
      compare(item.outlined, undefined, "no `outlined` property");
    }
  }

  function test_segment_blocks_have_no_border() {
    const segments = createTemporaryObject(segmentComp, root);
    verify(segments);
    const blocks = findAll(segments, it => it.objectName === "block");
    verify(blocks.length > 0, "SegmentMeter blocks are named");
    for (const block of blocks)
      compare(block.border.width, 0);
  }

  function findAll(item, match) {
    const out = [];
    const walk = it => {
      if (match(it))
        out.push(it);
      for (const child of it.children)
        walk(child);
    };
    walk(item);
    return out;
  }

  // The trough reads against the OSD's own fill (Style.surfacePage, what
  // EdgePopout draws) and against Style.surface (the tile it sits on), with
  // the highest-vs-surface floors of tst_StyleTokens
  function test_trough_reads_against_what_it_sits_on_data() {
    return [
      {
        "tag": "dark mocha",
        "theme": "catppuccin-mocha",
        "min": 1.20
      },
      {
        "tag": "dark nord",
        "theme": "nord",
        "min": 1.20
      },
      {
        "tag": "light latte",
        "theme": "catppuccin-latte",
        "min": 1.45
      },
      {
        "tag": "light github",
        "theme": "github-light",
        "min": 1.45
      }
    ];
  }

  function test_trough_reads_against_what_it_sits_on(data) {
    harness.configure({
      "theme": data.theme
    });
    const onOsd = Tone.contrast(Style.trough, Style.surfacePage);
    const onTile = Tone.contrast(Style.trough, Style.surface);
    verify(onTile >= data.min, `${data.theme}: trough vs surface ${onTile.toFixed(2)}`);
    verify(onOsd >= data.min - 0.05, `${data.theme}: trough vs the OSD fill ${onOsd.toFixed(2)}`);
    verify(!Qt.colorEqual(Style.trough, Style.surfacePage));
    harness.configure({});
  }

  function test_muted_trough_reads_on_highest() {
    const bar = createTemporaryObject(barComp, root, {
      "isMuted": true
    });
    const trough = findChild(bar, "trough");
    verify(trough);
    tryVerify(() => Qt.colorEqual(trough.color, Style.inkHighest.divider));
    verify(!Qt.colorEqual(trough.color, Style.surfaceHighest));
  }

  // Pomodoro's dots: four, two done
  function test_segments_as_pomodoro_sets_them() {
    const dots = createTemporaryObject(segmentComp, root, {
      "count": 4,
      "share": 2 / 4,
      "round": true,
      "height": 10,
      "width": 46
    });
    verify(dots);
    compare(dots.lit, 2);
  }
}
