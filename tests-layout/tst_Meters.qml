import QtQuick
import QtTest
import qs.config
import qs.components.reusable

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

  function test_troughIsOneRole() {
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

  function test_noOutline() {
    for (const comp of [sliderComp, levelComp, segmentComp, ringComp, barComp]) {
      const item = createTemporaryObject(comp, root);
      verify(item);
      verify(!item.hasOwnProperty("outlined"));
    }
  }

  function test_mutedTroughReadsOnHighest() {
    const bar = createTemporaryObject(barComp, root, {
      "isMuted": true
    });
    const trough = findChild(bar, "trough");
    verify(trough);
    tryVerify(() => Qt.colorEqual(trough.color, Style.inkHighest.divider));
    verify(!Qt.colorEqual(trough.color, Style.surfaceHighest));
  }

  // Pomodoro's dots: four, two done
  function test_segmentsAsPomodoroSetsThem() {
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
