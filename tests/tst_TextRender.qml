import QtQuick
import QtTest
import qs.components.methods

// TextRender: the zoom a text is drawn at (the product of the `contentZoom`s
// above it) and the render type that follows. The pieces import Quickshell
// and stay out of this pure run, so StyledText's own `renderType` is read in
// the layout harness.
TestCase {
  id: root

  name: "TextRender"
  when: windowShown

  Component {
    id: zoomComp

    Item {
      property real contentZoom: 1
    }
  }

  Component {
    id: textComp

    Item {
      readonly property real zoom: TextRender.zoomAt(parent)
    }
  }

  Component {
    id: loaderComp

    Item {
      property real contentZoom: 0.5
      property alias loader: loader

      Loader {
        id: loader

        sourceComponent: textComp
      }
    }
  }

  Component {
    id: repeaterComp

    Item {
      property real contentZoom: 0.5
      property alias repeater: repeater

      Repeater {
        id: repeater

        model: 1
        delegate: textComp
      }
    }
  }

  function test_no_host_is_one() {
    compare(TextRender.zoomAt(null), 1);
    const plain = createTemporaryObject(textComp, root);
    compare(plain.zoom, 1);
  }

  function test_nested_product() {
    const outer = createTemporaryObject(zoomComp, root);
    outer.contentZoom = 0.9;
    const inner = zoomComp.createObject(outer);
    inner.contentZoom = 0.8;
    const text = textComp.createObject(inner);
    fuzzyCompare(text.zoom, 0.72, 1e-9);
    fuzzyCompare(TextRender.zoomAt(outer), 0.9, 1e-9);
  }

  function test_loader_and_repeater() {
    const ld = createTemporaryObject(loaderComp, root);
    tryVerify(() => ld.loader.item !== null);
    compare(ld.loader.item.zoom, 0.5);
    const rep = createTemporaryObject(repeaterComp, root);
    compare(rep.repeater.itemAt(0).zoom, 0.5);
  }

  function test_reparent_reruns() {
    const host = createTemporaryObject(zoomComp, root);
    host.contentZoom = 0.9;
    const holder = createTemporaryObject(textComp, null);
    const text = textComp.createObject(holder);
    compare(text.zoom, 1);
    holder.parent = host;
    compare(text.zoom, 0.9);
    holder.parent = null;
    compare(text.zoom, 1);
    holder.destroy();
  }

  function test_type_for() {
    compare(TextRender.typeFor(1, false, 0), Text.NativeRendering);
    compare(TextRender.typeFor(1.005, false, 0), Text.NativeRendering);
    compare(TextRender.typeFor(0.995, false, 0), Text.NativeRendering);
    compare(TextRender.typeFor(0.9, false, 0), Text.QtRendering);
    // a filled symbol stays native zoomed, an unfilled one does not
    compare(TextRender.typeFor(0.9, true, 1), Text.NativeRendering);
    compare(TextRender.typeFor(0.9, true, 0), Text.QtRendering);
    compare(TextRender.typeFor(0.9, false, 1), Text.QtRendering);
  }

  Component {
    id: publisherComp

    Item {
      id: publisher

      property real contentZoom: 1
      readonly property real drawnZoom: publisher.contentZoom * TextRender.zoomAt(publisher.parent)
    }
  }

  // The walk stops at a publisher and multiplies its drawnZoom
  function test_stops_at_drawn_zoom() {
    const outer = createTemporaryObject(zoomComp, root);
    outer.contentZoom = 0.5;
    const pub = publisherComp.createObject(outer);
    pub.contentZoom = 1;
    const text = textComp.createObject(pub);
    fuzzyCompare(text.zoom, 0.5, 1e-9);
    // below a publisher whose value is set apart from the walk
    const fixed = createTemporaryObject(zoomComp, root);
    fixed.contentZoom = 0.1;
    const item = Qt.createQmlObject("import QtQuick; Item { property real drawnZoom: 3 }", fixed);
    const t2 = textComp.createObject(item);
    fuzzyCompare(t2.zoom, 3, 1e-9);
  }

  // A publisher's own contentZoom is not counted twice
  function test_publisher_zoom_counted_once() {
    const host = createTemporaryObject(zoomComp, root);
    host.contentZoom = 0.5;
    const pub = publisherComp.createObject(host);
    pub.contentZoom = 2;
    const text = textComp.createObject(pub);
    fuzzyCompare(pub.drawnZoom, 1, 1e-9);
    fuzzyCompare(text.zoom, 1, 1e-9);
  }

  // The resize case: an ancestor's contentZoom above a relay updates the text
  function test_zoom_above_relay_updates() {
    const host = createTemporaryObject(zoomComp, root);
    host.contentZoom = 0.5;
    const pub = publisherComp.createObject(host);
    const text = textComp.createObject(pub);
    fuzzyCompare(text.zoom, 0.5, 1e-9);
    host.contentZoom = 0.8;
    fuzzyCompare(text.zoom, 0.8, 1e-9);
  }
}
