import QtQuick
import QtTest
import qs.config
import qs.components.reusable

// ZoomFrame: content at its natural size is scaled down to fit (never up),
// centred, and the scaled item declares its zoom.
TestCase {
  id: root

  name: "ZoomFrame"
  when: windowShown
  visible: true
  width: 600
  height: 400

  Component {
    id: frameComp

    ZoomFrame {
      naturalWidth: 400
      naturalHeight: 200

      Rectangle {
        objectName: "content"
        anchors.fill: parent
      }
    }
  }

  function make(w, h, extra) {
    const frame = createTemporaryObject(frameComp, root, Object.assign({
      "width": w,
      "height": h
    }, extra ?? ({})));
    waitForRendering(frame);
    return frame;
  }

  function test_fits_width() {
    const frame = make(200, 400);
    fuzzyCompare(frame.zoom, 0.5, 0.001);
    const at = frame.children[0].mapToItem(frame, 0, 0);
    fuzzyCompare(at.y, (400 - 200 * 0.5) / 2, 0.5, "centred");
  }

  function test_fits_height() {
    const frame = make(800, 50);
    fuzzyCompare(frame.zoom, 0.25, 0.001);
  }

  function test_never_scales_up() {
    const frame = make(1000, 800);
    compare(frame.zoom, 1);
    const scaled = frame.children[0];
    compare(scaled.contentZoom, 1);
    fuzzyCompare(scaled.x, 300, 0.5, "centred");
  }

  function test_declares_contentZoom() {
    const frame = make(100, 400);
    fuzzyCompare(frame.children[0].contentZoom, 0.25, 0.001);
  }

  function test_maxZoom_scales_up() {
    const frame = make(800, 800, {
      "maxZoom": Infinity
    });
    fuzzyCompare(frame.zoom, 2, 0.001);
    fuzzyCompare(frame.children[0].contentZoom, 2, 0.001);
  }

  function test_minZoom_floors() {
    const frame = make(20, 400, {
      "minZoom": 0.2
    });
    fuzzyCompare(frame.zoom, 0.2, 0.001);
  }
}
