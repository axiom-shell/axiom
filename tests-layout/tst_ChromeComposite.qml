import QtQuick
import QtTest
import qs.components.hosts.popout
import qs.components.methods
import qs.components.reusable
import qs.config
import qs.services.core

// The backing window's chrome composite (BlurBackingWindow's chrome copies +
// ChromeComposite), as pixels: real BlurShapes over real sources
// (AttachedSurfaces, Rectangles, a frame fixture), drawn by the real `Copies`
// (a fill opaque in premultiplied colour, then the stroke blended over it; the
// same in grey for the alpha capture), z by PaintOrder, strokes cut by
// HoledCopy, over the BlurManager layout stub. Where the
// scene graph is GPU-backed (scripts/run_tests.sh runs this file under xvfb
// with llvmpipe when it is installed) the two captures go through the real
// ChromeComposite and its shader, sampled 1:1. Under the offscreen platform Qt
// Quick renders in software, where a ShaderEffect draws nothing and a clipped
// Shape is drawn wrong (so the rows through HoledCopy skip there, with a reason
// that starts `software scene graph:`, which CI fails on): each
// capture is then grabbed over black (its premultiplied rgb) and the shader's
// one line (rgb of the colour capture, r of the alpha capture) applied here;
// chrome-composite.frag's build is scripts/check_shaders.py's. Rows name the
// scale they run at (run_tests.sh runs this file at 1 and at 1.25): positions
// are read at the middle of a logical pixel.
TestCase {
  id: root

  name: "ChromeComposite"
  when: windowShown
  visible: true
  width: 400
  height: 300

  readonly property real dpr: root.Window.window?.devicePixelRatio ?? 1
  // A GPU-backed scene graph: the real ChromeComposite draws
  readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
  // The tolerance, in 8-bit levels (a grab's unit)
  readonly property int tol: 2

  Harness {
    id: harness
  }

  // Hidden holder of the sources the copies mirror
  Item {
    id: sources
    visible: false
  }

  Component {
    id: surfaceComp

    AttachedSurface {
      edge: ScreenEdge.Top
      active: true
      boxWidth: 120
      boxHeight: 60
    }
  }

  // One chrome capture: the real `Copies` of `shapes`, over
  // black when read as pixels in software
  Component {
    id: layerComp

    Item {
      id: layer
      property var shapes: []
      property bool asAlpha: false
      property bool backdrop: true
      property color backColor: "black"
      property string draws: "chrome"
      property alias copies: copies

      Rectangle {
        anchors.fill: parent
        visible: layer.backdrop
        color: layer.backColor
      }

      Copies {
        id: copies
        screen: ""
        shapes: layer.shapes
        draws: layer.draws
        asAlpha: layer.asAlpha
      }
    }
  }

  // The scene: both captures of `shapes` and, where the scene graph
  // is GPU-backed, the real ChromeComposite over `back`. The two
  // `ShaderEffectSource`s are written as BlurBackingWindow's `colorCapture` and
  // `alphaCapture` have them: harness plumbing, not a second rule. Without a GPU the layers sit
  // one over the other, each grabbed over black.
  Component {
    id: sceneComp

    Item {
      id: scene
      property var shapes: []
      property color back: "black"
      property real lw: 160
      property real lh: 100
      readonly property Item colorLayer: colorLoader.item
      readonly property Item alphaLayer: alphaLoader.item
      readonly property Item hold: hold
      // (whole device px, as a window's size is: a capture's scale is then dpr)
      width: Math.ceil(scene.lw * root.dpr) / root.dpr
      height: Math.ceil(scene.lh * root.dpr) / root.dpr

      // Where the rect sources live
      Item {
        id: hold
        visible: false
      }
      Rectangle {
        anchors.fill: parent
        visible: root.gpu
        color: scene.back
      }
      Loader {
        id: colorLoader
        width: scene.width
        height: scene.height
        sourceComponent: layerComp
        onLoaded: {
          item.shapes = Qt.binding(() => scene.shapes);
          item.backdrop = !root.gpu;
          item.asAlpha = false;
        }
      }
      Loader {
        id: alphaLoader
        y: root.gpu ? 0 : scene.height + 10
        width: scene.width
        height: scene.height
        sourceComponent: layerComp
        onLoaded: {
          item.shapes = Qt.binding(() => scene.shapes);
          item.backdrop = !root.gpu;
          item.asAlpha = true;
        }
      }
      ShaderEffectSource {
        id: colorCapture
        anchors.fill: parent
        visible: false
        sourceItem: root.gpu ? colorLoader.item : null
        hideSource: true
        smooth: false
        textureSize: Qt.size(Math.ceil(scene.width * root.dpr), Math.ceil(scene.height * root.dpr))
      }
      ShaderEffectSource {
        id: alphaCapture
        anchors.fill: parent
        visible: false
        sourceItem: root.gpu ? alphaLoader.item : null
        hideSource: true
        smooth: false
        textureSize: colorCapture.textureSize
      }
      ChromeComposite {
        anchors.fill: parent
        visible: root.gpu
        colorSource: colorCapture
        alphaSource: alphaCapture
      }
    }
  }

  // The source of a rect shape: a Rectangle with its radii, its own border
  // where the source draws one (a toast card), and the stroke holes a
  // publisher sets (as BarContainer's island and inner-stroke sources declare it)
  Component {
    id: rectSourceComp

    Rectangle {
      property var strokeHoles: []
      color: "transparent"
    }
  }

  Component {
    id: copyComp

    AttachedSurfaceCopy {}
  }

  Component {
    id: shapeComp

    BlurShape {}
  }

  // A spec's fill and stroke as colours
  function fillColor(f) {
    return Qt.rgba(f.c.r, f.c.g, f.c.b, f.a);
  }
  function strokeColor(s) {
    return s ? Qt.rgba(s.c.r, s.c.g, s.c.b, s.a) : "transparent";
  }

  // The real BlurShape of `spec` { kind, rank, src | w, h, radius, bw,
  // onItself, x, y, fill, stroke, holes, opacity }, over its real source
  function shapeFor(spec, scene) {
    let source = spec.src;
    if (spec.kind === "rect") {
      source = rectSourceComp.createObject(scene.hold, {
        "width": spec.w,
        "height": spec.h,
        "radius": spec.radius ?? 0
      });
      source.border.width = spec.onItself ? spec.bw : 0;
    }
    if (spec.kind !== "frame")
      source.strokeHoles = spec.holes ?? [];
    if (spec.kind === "attached")
      source.hostOpacity = spec.opacity ?? 1;
    return shapeComp.createObject(scene, Object.assign({
      "source": source,
      "kind": spec.kind,
      "color": root.fillColor(spec.fill ?? {
        "c": Qt.rgba(0, 0, 0, 1),
        "a": 0
      }),
      "strokeColor": root.strokeColor(spec.stroke),
      "paintRank": PaintOrder.rankOf(spec.rank),
      "x": spec.x ?? 0,
      "y": spec.y ?? 0,
      "clipRect": spec.clip ?? null
    }, spec.fillClip ? {
      "fillClip": spec.fillClip
    } : {}));
  }

  function surface(props) {
    return createTemporaryObject(surfaceComp, sources, props ?? {});
  }
  // The holed rows use a small surface (60 × 30 box, 72 × 36 with its fillets,
  // its far wall's stroke at y 29 of it, 34 on screen at (10, 5)): the software
  // scene graph these tests run on draws a stroke wrong in a clipped item as
  // big as HoledCopy's pieces are for a large one (the same pieces under a
  // GPU-backed scene graph, llvmpipe's, are exact)
  function smallSurface() {
    return root.surface({
      "boxWidth": 60,
      "boxHeight": 30
    });
  }
  readonly property var hole: Qt.rect(20, 26, 30, 6)

  // A scene of `specs` (`opts`: { w, h }, its logical size)
  function makeScene(specs, opts) {
    const scene = createTemporaryObject(sceneComp, root, {
      "lw": opts?.w ?? 160,
      "lh": opts?.h ?? 100
    });
    scene.shapes = specs.map(spec => root.shapeFor(spec, scene));
    return scene;
  }

  // An item with a `back` colour as (xd, yd) -> { r, g, b, a } (premultiplied, 0-1), from a grab over black and one over white
  function grabPremultiplied(item) {
    item.back = "black";
    waitForRendering(item);
    const onBlack = grabImage(item);
    item.back = "white";
    waitForRendering(item);
    const onWhite = grabImage(item);
    return (xd, yd) => ({
          "r": onBlack.red(xd, yd) / 255,
          "g": onBlack.green(xd, yd) / 255,
          "b": onBlack.blue(xd, yd) / 255,
          // (over white, a pixel is rgb + (1 - a))
          "a": 1 - (onWhite.red(xd, yd) - onBlack.red(xd, yd)) / 255
        });
  }

  // The composite of `scene` as { px(x, y) -> { r, g, b, a } (premultiplied, 0-1), dpx(xd, yd) the same at a device
  // pixel }, x and y logical, read at the middle of their pixel
  function capture(scene) {
    const at = v => Math.floor((v + 0.5) * root.dpr);
    let grab;
    if (root.gpu) {
      grab = root.grabPremultiplied(scene);
    } else {
      // (each capture a layer of its own, apart from the scene: a grab of the
      // scene's two layers returns the first twice here)
      const layer = asAlpha => createTemporaryObject(layerComp, root, {
          "width": scene.width,
          "height": scene.height,
          "shapes": scene.shapes,
          "asAlpha": asAlpha,
          "y": asAlpha ? scene.height + 10 : 0
        });
      const colorGrab = layer(false), alphaGrab = layer(true);
      waitForRendering(colorGrab);
      waitForRendering(alphaGrab);
      const c = grabImage(colorGrab), a = grabImage(alphaGrab);
      colorGrab.destroy();
      alphaGrab.destroy();
      grab = (xd, yd) => ({
            "r": c.red(xd, yd) / 255,
            "g": c.green(xd, yd) / 255,
            "b": c.blue(xd, yd) / 255,
            "a": a.red(xd, yd) / 255
          });
    }
    return {
      "px": (x, y) => grab(at(x), at(y)),
      "dpx": grab
    };
  }

  function render(specs, opts) {
    return root.capture(root.makeScene(specs, opts));
  }

  // A difference of two grabbed values (0-1) in 8-bit levels. The grabs are
  // whole levels, and |a/255 - b/255| against n/255 in float misreads a
  // difference of exactly n levels as more
  function levels(d) {
    return Math.round(Math.abs(d) * 255);
  }

  // The most any channel of two grabbed pixels differs, in levels
  function pixelOff(c, w) {
    return Math.max(...["r", "g", "b", "a"].map(k => root.levels(c[k] - w[k])));
  }

  function near(got, want, what) {
    for (const k of ["r", "g", "b", "a"])
      verify(root.levels(got[k] - want[k]) <= root.tol, `${what}: ${k} ${got[k].toFixed(4)} vs ${want[k].toFixed(4)}`);
  }

  // A stroke `s` (colour, alpha) over what `under` holds (premultiplied)
  function over(s, under) {
    return {
      "r": s.c.r * s.a + (1 - s.a) * under.r,
      "g": s.c.g * s.a + (1 - s.a) * under.g,
      "b": s.c.b * s.a + (1 - s.a) * under.b,
      "a": s.a + (1 - s.a) * under.a
    };
  }
  function filled(f) {
    return {
      "r": f.c.r * f.a,
      "g": f.c.g * f.a,
      "b": f.c.b * f.a,
      "a": f.a
    };
  }

  readonly property var blue: ({
      "c": Qt.rgba(0.12, 0.2, 0.6, 1),
      "a": 0.8
    })
  readonly property var green: ({
      "c": Qt.rgba(0.2, 0.6, 0.3, 1),
      "a": 0.5
    })
  readonly property var solid: ({
      "c": Qt.rgba(0.6, 0.3, 0.1, 1),
      "a": 1
    })
  function line(a) {
    return {
      "c": Qt.rgba(0.9, 0.7, 0.2, 1),
      "a": a
    };
  }

  property bool strokeSet: false

  function initTestCase() {
    harness.configure({});
  }
  // A row's stroke width (Appearance.borderWidth), back to the default after it
  // The software scene graph draws a fractional scale wrong: those rows are read through the real shader
  function needsGpuAtFractional() {
    if (!root.gpu && root.dpr !== 1)
      skip("software scene graph: the fractional scale is read through the real shader only");
  }
  function setStroke(width) {
    const live = JSON.parse(JSON.stringify(ConfigManager.live));
    live.Appearance.shape.borderWidth = width;
    ConfigManager.live = live;
    root.strokeSet = true;
  }
  function cleanup() {
    if (root.strokeSet) {
      harness.configure({});
      root.strokeSet = false;
    }
  }

  // ---- the composite's values (Why it holds both ways) ----

  // A stroke pixel inside one shape (over its own fill), fill alpha 0.8, stroke alpha 1 and 0.5
  function test_stroke_over_own_fill_data() {
    return [
      {
        "tag": "a_s 1",
        "a": 1
      },
      {
        "tag": "a_s 0.5",
        "a": 0.5
      }
    ];
  }
  function test_stroke_over_own_fill(data) {
    if (root.dpr !== 1 && !root.gpu)
      skip("software scene graph: the fractional scale is read through the real shader only");
    root.setStroke(2);
    const s = root.line(data.a);
    const px = root.render([
      {
        "kind": "rect",
        "rank": "bar",
        "x": 10,
        "y": 10,
        "w": 80,
        "h": 50,
        "bw": 2,
        "fill": root.blue,
        "stroke": s
      }
    ]);
    root.near(px.px(50, 10), root.over(s, root.filled(root.blue)), "on the stroke");
    root.near(px.px(50, 11), root.over(s, root.filled(root.blue)), "on the stroke's second row");
    root.near(px.px(50, 30), root.filled(root.blue), "the fill beside it");
    root.near(px.px(5, 5), {
      "r": 0,
      "g": 0,
      "b": 0,
      "a": 0
    }, "nothing outside");
  }

  // The lower shape's stroke under the upper shape's fill: no trace; two fills overlapping: the upper's alone
  function test_lower_stroke_under_upper_fill_data() {
    return [
      {
        "tag": "opaque",
        "up": root.solid
      },
      {
        "tag": "alpha 0.5 each",
        "up": root.green
      }
    ];
  }
  function test_lower_stroke_under_upper_fill(data) {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const lower = {
      "kind": "rect",
      "rank": "bar",
      "x": 10,
      "y": 10,
      "w": 80,
      "h": 50,
      "bw": 2,
      "fill": root.green,
      "stroke": root.line(1)
    };
    const upper = {
      "kind": "rect",
      "rank": "surface",
      "x": 40,
      "y": 5,
      "w": 40,
      "h": 30,
      "fill": data.up
    };
    const px = root.render([lower, upper]);
    // Under the upper's fill lies the lower's top stroke (y 10-11): the upper's value alone
    root.near(px.px(60, 10), root.filled(data.up), "no trace of the lower stroke");
    root.near(px.px(60, 20), root.filled(data.up), "two fills: the upper's");
    // Beside it the lower stroke is whole
    root.near(px.px(20, 10), root.over(root.line(1), root.filled(root.green)), "the lower stroke where nothing covers it");
  }

  // The order the shapes are registered in decides nothing: the rank does
  function test_levels_not_registration() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    root.setStroke(2);
    const bar = {
      "kind": "rect",
      "rank": "base",
      "x": 10,
      "y": 10,
      "w": 100,
      "h": 30,
      "fill": root.blue
    };
    // A solid bar's inner stroke: a stroke-only rect over its fill
    const stroke = {
      "kind": "rect",
      "rank": "frame",
      "x": 10,
      "y": 36,
      "w": 100,
      "h": 4,
      "bw": 2,
      "fill": {
        "c": Qt.rgba(0, 0, 0, 1),
        "a": 0
      },
      "stroke": root.line(0.5)
    };
    const one = root.render([bar, stroke]).px(50, 39);
    const other = root.render([stroke, bar]).px(50, 39);
    root.near(one, root.over(root.line(0.5), root.filled(root.blue)), "the stroke over the fill, the fill first");
    root.near(other, one, "the same either order");
  }

  // A toast card (rank toast, its own border) over a dock's copy (rank surface), in both orders
  function test_toast_over_dock() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const dock = {
      "kind": "attached",
      "rank": "surface",
      "src": root.surface(),
      "x": 10,
      "y": 5,
      "fill": root.blue,
      "stroke": root.line(1)
    };
    const card = {
      "kind": "rect",
      "rank": "toast",
      "x": 30,
      "y": 20,
      "w": 80,
      "h": 40,
      "bw": 1,
      "onItself": true,
      "fill": root.solid,
      "stroke": root.line(1)
    };
    const a = root.render([dock, card]), b = root.render([card, dock]);
    for (const p of [[40, 40], [31, 40], [30, 30], [60, 59], [100, 45]])
      root.near(a.px(p[0], p[1]), b.px(p[0], p[1]), `same either order at ${p}`);
    root.near(a.px(60, 40), root.filled(root.solid), "the card's fill over the dock");
    root.near(a.px(60, 20), root.line(1).a === 1 ? {
      "r": 0.9,
      "g": 0.7,
      "b": 0.2,
      "a": 1
    } : a.px(60, 20), "the card's border");
  }

  // ---- the stroke holes (D-3.18) ----

  // The far stroke of a popout copy (the attached surface's box 60 deep, its
  // far wall's stroke at y 59, in its coordinates)
  function holedScenes(holes, strokeA) {
    const s = root.line(strokeA);
    const src = root.smallSurface();
    const lower = (stroke, h) => ({
          "kind": "attached",
          "rank": "bar",
          "src": src,
          "x": 10,
          "y": 5,
          "fill": root.blue,
          "stroke": stroke,
          "holes": h
        });
    return {
      "cut": root.render([lower(s, holes)]),
      "bare": root.render([lower(null, [])]),
      "whole": root.render([lower(s, [])])
    };
  }

  function test_cut_takes_the_stroke_alone_data() {
    return [
      {
        "tag": "a_s 1",
        "a": 1
      },
      {
        "tag": "a_s 0.5",
        "a": 0.5
      }
    ];
  }
  function test_cut_takes_the_stroke_alone(data) {
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    if (root.dpr !== 1)
      skip("scale 1 row");
    const scenes = root.holedScenes([root.hole], data.a);
    for (const x of [32, 40, 48, 58])
      root.near(scenes.cut.px(x, 34), scenes.bare.px(x, 34), `in the hole, x ${x}: the lower fill alone`);
    // Across the stroke, 2 px either side of it: no trace
    for (const y of [32, 33, 35, 36])
      root.near(scenes.cut.px(45, y), scenes.bare.px(45, y), `across the stroke, y ${y}`);
    // Just outside each end of the span the stroke is whole
    for (const x of [28, 62])
      root.near(scenes.cut.px(x, 34), scenes.whole.px(x, 34), `the stroke just outside the span, x ${x}`);
    verify(Math.abs(scenes.whole.px(28, 34).a - scenes.bare.px(28, 34).a) > 0.05, "the stroke shows where it isn't cut");
  }

  // The pieces: outside the holes every pixel equals the same scene with no holes, at 1 and 1.25
  function test_pieces_are_the_stroke() {
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    const scenes = root.holedScenes([root.hole], 0.5);
    let off = 0, count = 0;
    for (let y = 5; y < 45; y++) {
      for (let x = 10; x < 85; x++) {
        // (the hole's rect on screen: x 30-60, y 31-37, with a pixel round it)
        if (x >= 29 && x <= 60 && y >= 30 && y <= 37)
          continue;
        const c = scenes.cut.px(x, y), w = scenes.whole.px(x, y);
        count++;
        if (root.pixelOff(c, w) > 1)
          off++;
      }
    }
    verify(count > 1000);
    compare(off, 0, `${off} of ${count} pixels differ from the scene with no holes (scale ${root.dpr})`);
  }

  Component {
    id: changedSpyComp

    SignalSpy {}
  }

  // The copy's holes follow its source's: an equal list pushed again (as the
  // publishers do on every opening change) is no change; a different one is
  function test_equal_holes_pushed_again_change_nothing() {
    const src = root.smallSurface();
    const h = [Qt.rect(20, 26, 30, 6)];
    const scene = root.makeScene([root.attachedSpec(src, "surface", root.solid, root.line(1), h)]);
    wait(0);
    const spy = createTemporaryObject(changedSpyComp, root, {
      "target": scene.colorLayer.copies,
      "signalName": "changed"
    });
    src.strokeHoles = h.map(r => Qt.rect(r.x, r.y, r.width, r.height));
    wait(0);
    compare(spy.count, 0);
    src.strokeHoles = [Qt.rect(20, 26, 10, 6)];
    wait(0);
    verify(spy.count > 0);
  }

  // Holes at a fractional logical edge (x 12.3) and at a half device pixel at 1.25 (x 36.4 and y 26.4: 45.5 and
  // 33 device px), under a fractional copy origin: outside the holes (a pixel grown round each) every device
  // pixel equals the same scene with no holes within 1/255
  function test_fractional_holes_are_the_stroke() {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    const holes = [Qt.rect(12.3, 26.4, 10, 6), Qt.rect(36.4, 26.4, 10, 6)];
    const src = root.smallSurface();
    const lower = (stroke, h) => ({
          "kind": "attached",
          "rank": "bar",
          "src": src,
          "x": 10.3,
          "y": 5.2,
          "fill": root.blue,
          "stroke": stroke,
          "holes": h
        });
    const cut = root.render([lower(root.line(0.5), holes)]);
    const whole = root.render([lower(root.line(0.5), [])]);
    const near = (x, y) => holes.some(h => x >= 10.3 + h.x - 1 && x <= 10.3 + h.x + h.width + 1 && y >= 5.2 + h.y - 1 && y <= 5.2 + h.y + h.height + 1);
    let off = 0, count = 0;
    const first = [];
    for (let yd = 6; yd < 56; yd++) {
      for (let xd = 12; xd < 106; xd++) {
        if (near((xd + 0.5) / root.dpr, (yd + 0.5) / root.dpr))
          continue;
        const c = cut.dpx(xd, yd), w = whole.dpx(xd, yd);
        count++;
        if (root.pixelOff(c, w) > 1) {
          off++;
          if (first.length < 8)
            first.push(`${xd},${yd} (a ${c.a.toFixed(3)} vs ${w.a.toFixed(3)}, r ${c.r.toFixed(3)} vs ${w.r.toFixed(3)})`);
        }
      }
    }
    verify(count > 1000);
    compare(off, 0, `${off} of ${count} device pixels differ from the scene with no holes, first at ${first.join(" ")}`);
  }

  // A fade: the copy at opacity 0.5 with its hole open: the hole shows the fill alone, whatever the opacity
  function test_cut_under_a_fade() {
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    if (root.dpr !== 1)
      skip("scale 1 row");
    const src = root.smallSurface();
    const copy = (stroke, holes) => ({
          "kind": "attached",
          "rank": "surface",
          "src": src,
          "x": 10,
          "y": 5,
          "fill": root.blue,
          "stroke": stroke,
          "holes": holes,
          "opacity": 0.5
        });
    const cut = root.render([copy(root.line(1), [root.hole])]);
    const bare = root.render([copy(null, [])]);
    root.near(cut.px(45, 34), bare.px(45, 34), "the hole at half opacity");
  }

  // ---- tiled menus: no copy, no hole (D-3.19) ----

  function test_tiles_leave_the_line_whole_data() {
    return [
      {
        "tag": "see-through",
        "a": 0.8
      },
      {
        "tag": "opaque",
        "a": 1
      }
    ];
  }
  function test_tiles_leave_the_line_whole(data) {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const src = root.surface();
    const fill = {
      "c": root.blue.c,
      "a": data.a
    };
    const pill = {
      "kind": "attached",
      "rank": "bar",
      "src": src,
      "x": 10,
      "y": 5,
      "fill": fill,
      "stroke": root.line(1)
    };
    const tile = x => ({
          "kind": "rect",
          "rank": "surface",
          "x": x,
          "y": 40,
          "w": 40,
          "h": 30,
          "radius": 4,
          "fill": root.solid
        });
    const alone = root.render([pill]);
    const tiled = root.render([pill, tile(20), tile(70)]);
    // The pill's far stroke at y 64: in the gap (x 60-70) it is as with no tiles, under a tile the tile's
    for (const x of [62, 65, 68])
      root.near(tiled.px(x, 64), alone.px(x, 64), `the line unbroken in the gap, x ${x}`);
    root.near(tiled.px(40, 64), root.filled(root.solid), "under a tile, the tile's value");
  }

  // ---- the must-not rows: no gap, line or break may show where a popout joins the bar or border ----

  // A real AttachedSurface placed at (x, y) in the scene, as its host would
  function placed(props, x, y) {
    return root.surface(Object.assign({
      "x": x,
      "y": y
    }, props));
  }
  function settle(surfaces) {
    for (const surface of surfaces)
      tryVerify(() => surface.slid === 0, 3000);
  }
  function attachedSpec(src, rank, fill, stroke, holes) {
    return {
      "kind": "attached",
      "rank": rank,
      "src": src,
      "x": src.x,
      "y": src.y,
      "fill": fill,
      "stroke": stroke,
      "holes": holes ?? []
    };
  }

  // The joined cases, geometry from real AttachedSurfaces placed by hand, the
  // holes on the lower source as its publisher sets them. Each gives
  // `specs(sa, fa, stroke, cut)` (the scene with the lower stroke drawn or
  // not, its holes set or not) and `bands`: each hole's rect on screen, whether
  // it runs down, the width of the fringe it takes either side of the stroke,
  // and which of its ends have the lower stroke running on past them
  function joinCase(name) {
    const sw = Appearance.borderWidth;
    const fills = fa => ({
          "low": {
            "c": root.blue.c,
            "a": fa
          },
          "up": {
            "c": root.green.c,
            "a": fa
          }
        });
    if (name === "popout on a pill") {
      const pill = root.placed({
        "boxWidth": 100,
        "boxHeight": 18
      }, 20, 4);
      const pop = root.placed({
        "boxWidth": 50,
        "boxHeight": 40
      }, 48, 4 + pill.farV - pill.half);
      root.settle([pill, pop]);
      // the pill's far stroke and its fringe under the popout (BarContainer's _farHole)
      const across = EdgeAttach.strokeHoleAcross(pill.farV - pill.half, pill.strokeWidth);
      const hole = pill._rectFrom(pop.x + pop.coverStart - pill.x, across.start, pop.coverEnd - pop.coverStart, across.size);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(pill, "bar", fills(fa).low, stroke ? root.line(sa) : null, cut ? [hole] : []), root.attachedSpec(pop, "surface", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": Qt.rect(pill.x + hole.x, pill.y + hole.y, hole.width, hole.height),
            "vertical": false,
            "fringe": 1,
            "ends": [true, true]
          }
        ]
      };
    }
    if (name === "submenu on a popout's side") {
      const par = root.placed({
        "boxWidth": 70,
        "boxHeight": 60
      }, 20, 4);
      // (its box's side on a whole pixel, as a host places it)
      par.x = 20 + Math.ceil(par.startMargin) - par.startMargin;
      const wall = par.x + par.startMargin + par.boxWidth;
      const sub = root.placed({
        "edge": ScreenEdge.Left,
        "boxWidth": 36,
        "boxHeight": 24
      }, wall - sw, par.y + 14);
      root.settle([par, sub]);
      // the wall's stroke and its fringe where the submenu covers it (SubPopout.parentHole)
      const across = EdgeAttach.strokeHoleAcross(wall - sw, sw);
      const win = Qt.rect(across.start, sub.y + sub.coverStart, across.size, sub.coverEnd - sub.coverStart);
      const holes = par.submenuHoles(win, false, false);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(par, "surface", fills(fa).low, stroke ? root.line(sa) : null, cut ? holes : []), root.attachedSpec(sub, "submenu", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": win,
            "vertical": true,
            "fringe": 1,
            "ends": [true, true]
          }
        ]
      };
    }
    if (name === "popout on a solid bar's inner stroke") {
      const pop = root.placed({
        "boxWidth": 50,
        "boxHeight": 40
      }, 50, 16 - sw);
      root.settle([pop]);
      const start = pop.x + pop.coverStart, length = pop.coverEnd - pop.coverStart;
      // the inner-stroke rect's own coordinates (BarContainer.solidStroke)
      const hole = Qt.rect(start, 0, length, sw);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [
            {
              "kind": "rect",
              "rank": "base",
              "x": 0,
              "y": 0,
              "w": 180,
              "h": 16,
              "fill": fills(fa).low
            },
            {
              "kind": "rect",
              "rank": "frame",
              "x": 0,
              "y": 16 - sw,
              "w": 180,
              "h": sw,
              "fill": {
                "c": root.blue.c,
                "a": 0
              },
              "stroke": stroke ? root.line(sa) : null,
              "holes": cut ? [hole] : []
            },
            root.attachedSpec(pop, "surface", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": Qt.rect(start, 16 - sw, length, sw),
            "vertical": false,
            "fringe": 0,
            "ends": [true, true]
          }
        ]
      };
    }
    if (name === "corner merge") {
      // a left bar's pill, running on past the screen's top edge (its end wall
      // off screen), and the top bar's end pill joined to its far stroke
      const left = root.placed({
        "edge": ScreenEdge.Left,
        "boxWidth": 18,
        "boxHeight": 80,
        "flushStart": true,
        "startCornerRadius": 0
      }, 0, -8);
      const top = root.placed({
        "boxWidth": 70,
        "boxHeight": 18,
        "joinStart": true
      }, left.farV + left.half, 0);
      root.settle([left, top]);
      const across = EdgeAttach.strokeHoleAcross(left.farV - left.half, left.strokeWidth);
      const hole = left._rectFrom(0, across.start, 8 + Math.floor(top.joinCover), across.size);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(left, "bar", fills(fa).low, stroke ? root.line(sa) : null, cut ? [hole] : []), root.attachedSpec(top, "cornerJoin", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": Qt.rect(left.x + hole.x, 0, hole.width, left.y + hole.y + hole.height),
            "vertical": true,
            "fringe": 1,
            "ends": [false, true]
          }
        ]
      };
    }
    if (name === "popout joined at an end to a pill bar's stub") {
      // a left bar's pill with square ends, and a top popout joined to it at
      // its start, its far wall's outer edge on the pill's box end: the stub's
      // square corner under that wall is cut (BarContainer's corner piece)
      const pill = root.placed({
        "edge": ScreenEdge.Left,
        "boxWidth": 18,
        "boxHeight": 70,
        "joinStart": true,
        "startCornerRadius": 0,
        "endCornerRadius": 0
      }, 0, -8);
      const pop = root.placed({
        "boxWidth": 60,
        "boxHeight": 40,
        "joinStart": true,
        "straightJoinStart": true
      }, pill.x + pill.farV - pill.half, 0);
      root.settle([pill, pop]);
      pop.y = pill.y + pill.boxRect.y + pill.boxRect.height - (pop.boxRect.y + pop.boxRect.height);
      compare(pop.y + pop.boxRect.y + pop.boxRect.height, pill.y + pill.boxRect.y + pill.boxRect.height);
      const wallOuter = pop.y + pop.boxRect.y + pop.boxRect.height;
      // the far stroke's band as BarContainer's _farHole takes it, under the opening PillBarJoin gives
      const across = EdgeAttach.strokeHoleAcross(pill.farV - pill.half, pill.strokeWidth);
      const o = SurfaceContext.opening(0, wallOuter - sw);
      const from = Math.max(o.start, pill.y);
      // (it stops a pixel short of the wall: BarContainer's farEnd)
      const band = pill._rectFrom(from - pill.y, across.start, o.end - 1 - from, across.size);
      // the corner under the wall, from where the popout's copy begins across the stroke (the pill's strokeHoles)
      const far = pill._rectFrom(0, pill.farV, 0, 0);
      const v = pill.farV + (pop.x - pill.x - far.x);
      const boxEnd = pill.alongLength - pill.endMargin;
      const corner = pill._rectFrom(o.end - 1 - pill.y, v, boxEnd + 1 - (o.end - 1 - pill.y), pill.farV + pill.half + 1 - v);
      // the wall's rows, from its inner edge to the row past its outer edge
      const wallRows = Qt.rect(pill.x + corner.x, pill.y + corner.y + 1, corner.width, corner.height - 1);
      compare(wallRows.y, wallOuter - sw);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(pill, "bar", fills(fa).low, stroke ? root.line(sa) : null, cut ? [band, corner] : []), root.attachedSpec(pop, "surface", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": wallRows,
            "vertical": false,
            "fringe": 0,
            "ends": [true, false]
          }
        ]
      };
    }
    if (name === "popout joined at the start of a pill bar's stub") {
      // the mirror: a left bar's pill with square ends running off the scene's
      // bottom, and a bottom popout joined to it at its end, its far wall's
      // outer edge on the pill's box start
      const pill = root.placed({
        "edge": ScreenEdge.Left,
        "boxWidth": 18,
        "boxHeight": 70,
        "joinEnd": true,
        "startCornerRadius": 0,
        "endCornerRadius": 0
      }, 0, 50);
      const pop = root.placed({
        "edge": ScreenEdge.Bottom,
        "boxWidth": 60,
        "boxHeight": 40,
        "joinStart": true,
        "straightJoinStart": true
      }, pill.x + pill.farV - pill.half, 0);
      root.settle([pill, pop]);
      pop.y = pill.y + pill.boxRect.y - pop.boxRect.y;
      compare(pop.y + pop.boxRect.y, pill.y + pill.boxRect.y);
      const wallOuter = pop.y + pop.boxRect.y;
      const across = EdgeAttach.strokeHoleAcross(pill.farV - pill.half, pill.strokeWidth);
      const o = SurfaceContext.opening(wallOuter + sw, pill.y + pill.alongLength);
      // (it starts a pixel past the wall: BarContainer's farStart)
      const band = pill._rectFrom(o.start + 1 - pill.y, across.start, o.end - o.start - 1, across.size);
      const far = pill._rectFrom(0, pill.farV, 0, 0);
      const v = pill.farV + (pop.x - pill.x - far.x);
      const corner = pill._rectFrom(pill.startMargin - 1, v, o.start + 1 - pill.y - pill.startMargin + 1, pill.farV + pill.half + 1 - v);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(pill, "bar", fills(fa).low, stroke ? root.line(sa) : null, cut ? [band, corner] : []), root.attachedSpec(pop, "surface", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": Qt.rect(pill.x + corner.x, wallOuter, corner.width, sw),
            "vertical": false,
            "fringe": 0,
            "ends": [true, false]
          }
        ]
      };
    }
    // the frame kinds: a fixture source, literal paths for one fixed
    // geometry (a 160 x 100 screen, a sharp 10 px border), which checks
    // `frameMirror` and `HoledCopy` on `kind: "frame"`, not RoundedBorders'
    // geometry
    const m = 10;
    const frame = frameComp.createObject(sources);
    if (name === "dock on the frame") {
      const dock = root.placed({
        "boxWidth": 60,
        "boxHeight": 30
      }, 50, m - sw);
      root.settle([dock]);
      // (the stroke's rows the strips leave open: EdgeAttach.strokeHoleAcross)
      const edge = EdgeAttach.strokeHoleAcross(m - sw, sw);
      const band = Qt.rect(dock.x + dock.coverStart, edge.start, dock.coverEnd - dock.coverStart, edge.size);
      const along = {
        "edge": "top",
        "start": band.x,
        "end": band.x + band.width
      };
      return {
        "w": 160,
        "h": 100,
        "specs": (sa, fa, stroke, cut) => [root.frameSpec(frame, fills(fa).low, stroke ? root.line(sa) : null, cut ? [along] : []), root.attachedSpec(dock, "surface", fills(fa).up, root.line(sa))],
        "bands": [
          {
            "rect": band,
            "vertical": false,
            "fringe": 1,
            "ends": [true, true]
          }
        ]
      };
    }
    // "a pill bar joined at a corner to the frame"
    const pill = root.placed({
      "boxWidth": 50,
      "boxHeight": 14,
      "joinStart": true
    }, m, m - sw);
    root.settle([pill]);
    const edge = EdgeAttach.strokeHoleAcross(m - sw, sw);
    const top = Qt.rect(pill.x + pill.coverStart, edge.start, pill.coverEnd - pill.coverStart, edge.size);
    const side = Qt.rect(edge.start, m + 1, edge.size, Math.floor(m - sw + pill.joinCover) - (m + 1));
    const openings = [
      {
        "edge": "top",
        "start": top.x,
        "end": top.x + top.width
      },
      {
        "edge": "left",
        "start": side.y,
        "end": side.y + side.height
      }
    ];
    return {
      "w": 160,
      "h": 100,
      "specs": (sa, fa, stroke, cut) => [root.frameSpec(frame, fills(fa).low, stroke ? root.line(sa) : null, cut ? openings : []), root.attachedSpec(pill, "surface", fills(fa).up, root.line(sa))],
      "bands": [
        {
          "rect": top,
          "vertical": false,
          "fringe": 1,
          "ends": [false, true]
        },
        {
          "rect": side,
          "vertical": true,
          "fringe": 1,
          "ends": [false, true]
        }
      ]
    };
  }

  // The four strips of a 160 x 100 screen with an `inset` px border, as
  // BorderPanel lays them out: the top and bottom ones across the width, the
  // side ones between them. Each { edge, origin (its window's top-left),
  // length }
  function strips(inset) {
    return [
      {
        "edge": "top",
        "origin": Qt.point(0, 0),
        "length": 160
      },
      {
        "edge": "bottom",
        "origin": Qt.point(0, 100 - inset),
        "length": 160
      },
      {
        "edge": "left",
        "origin": Qt.point(0, inset),
        "length": 100 - 2 * inset
      },
      {
        "edge": "right",
        "origin": Qt.point(160 - inset, inset),
        "length": 100 - 2 * inset
      }
    ];
  }
  // The frame's fixture source, carrying RoundedBorders' contract
  // (`strokeWidth`, `framePath`, `innerPath`, `strokeRects`, `cornerBoxes`),
  // with its `openings` ({ edge, start, end }, screen px), cut by the same
  // helpers RoundedBorders uses (`FrameOutline.screenStrokePieces`,
  // `cornerCovered`), its geometry FrameOutline's for a 160 x 100 screen with
  // an `inset` px border. At radius 0 that is a sharp border: the stroke
  // along the inner edge, inside the frame
  Component {
    id: frameComp

    Item {
      readonly property real strokeWidth: Appearance.borderWidth
      property var openings: []
      property real radius: 0
      property real inset: 10
      readonly property real innerBorderRadius: radius
      readonly property real cornerSize: FrameOutline.cornerSize(spec)
      // What RoundedBorders publishes, at this scale: the strips' stroke less
      // the openings on their edge (in the strip's window coordinates), and
      // the boxes of the corner windows no opening covers
      readonly property var strokeRects: [].concat(...root.strips(inset).map(st => {
        const horizontal = st.edge === "top" || st.edge === "bottom";
        const along = horizontal ? st.origin.x : st.origin.y;
        return FrameOutline.screenStrokePieces(st.edge, st.length, inset, radius, strokeWidth, openings.filter(o => o.edge === st.edge).map(o => ({
              "start": o.start - along,
              "end": o.end - along
            })), st.origin, root.dpr);
      }))
      readonly property var cornerBoxes: FrameOutline.corners.map(c => ({
            "box": FrameOutline.windowPixels(FrameOutline.cornerBox(spec, c.isLeft, c.isTop), root.dpr),
            "isLeft": c.isLeft,
            "isTop": c.isTop,
            "covered": FrameOutline.cornerCovered(spec, openings, c.isLeft, c.isTop)
          })).filter(c => !c.covered)
      readonly property var spec: ({
          "width": 160,
          "height": 100,
          "outerLeft": 0,
          "outerTop": 0,
          "outerRight": 0,
          "outerBottom": 0,
          "innerLeft": inset,
          "innerTop": inset,
          "innerRight": inset,
          "innerBottom": inset,
          "innerBorderRadius": radius,
          "strokeWidth": strokeWidth
        })
      function framePath(w, h, fromMenus) {
        return FrameOutline.framePath(spec, w, h, fromMenus);
      }
      function blurPieces(w, h) {
        return FrameOutline.blurRegion(spec, w, h);
      }
      function innerPath(w, h) {
        return FrameOutline.innerPath(spec, w, h);
      }
    }
  }

  function frameSpec(frame, fill, stroke, openings) {
    frame.openings = openings;
    return {
      "kind": "frame",
      "rank": "frame",
      "src": frame,
      "x": 0,
      "y": 0,
      "fill": fill,
      "stroke": stroke
    };
  }

  function eachPixel(rect, visit) {
    for (let y = Math.floor(rect.y); y < Math.ceil(rect.y + rect.height); y++) {
      for (let x = Math.floor(rect.x); x < Math.ceil(rect.x + rect.width); x++)
        visit(x, y);
    }
  }

  // No pixel along a line is lighter or darker than both its neighbours by more than 2/255
  function noSpike(values, what) {
    for (let i = 1; i < values.length - 1; i++) {
      for (const k of ["r", "g", "b", "a"]) {
        const up = values[i][k] - values[i - 1][k], down = values[i][k] - values[i + 1][k];
        verify(up * down <= 0 || root.levels(Math.min(Math.abs(up), Math.abs(down))) <= root.tol, `${what}: ${k} ${values[i][k].toFixed(4)} between ${values[i - 1][k].toFixed(4)} and ${values[i + 1][k].toFixed(4)}`);
      }
    }
  }

  function mustNotData() {
    const rows = [];
    for (const name of ["popout on a pill", "submenu on a popout's side", "popout on a solid bar's inner stroke", "corner merge", "popout joined at an end to a pill bar's stub", "popout joined at the start of a pill bar's stub", "dock on the frame", "pill bar joined to the frame"]) {
      for (const sw of [1, 2]) {
        for (const sa of [1, 0.5]) {
          for (const fa of [1, 0.8])
            rows.push({
              "tag": `${name}, stroke ${sw}, a_s ${sa}, fill ${fa}`,
              "name": name,
              "sw": sw,
              "sa": sa,
              "fa": fa
            });
        }
      }
    }
    return rows;
  }

  // The cut takes the lower stroke alone, where the upper surface covers it:
  // A (stroke drawn, cut) equals A' (stroke transparent, cut) in the hole's
  // rect grown 2 px across the stroke, and A'' (stroke transparent, no cut) in
  // the hole (the fill is left whole); just outside each end of the span the
  // stroke is whole (A equals the scene with no cut); and along the line
  // through each tip no pixel is lighter or darker than both its neighbours
  function test_must_not_data() {
    return root.mustNotData();
  }
  function test_must_not(data) {
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    root.setStroke(data.sw);
    const c = root.joinCase(data.name);
    const opts = {
      "w": c.w,
      "h": c.h
    };
    const cut = root.render(c.specs(data.sa, data.fa, true, true), opts);
    const clear = root.render(c.specs(data.sa, data.fa, false, true), opts);
    const bare = root.render(c.specs(data.sa, data.fa, false, false), opts);
    const whole = root.render(c.specs(data.sa, data.fa, true, false), opts);
    for (const band of c.bands) {
      const r = band.rect;
      const grown = band.vertical ? Qt.rect(r.x - 2, r.y, r.width + 4, r.height) : Qt.rect(r.x, r.y - 2, r.width, r.height + 4);
      root.eachPixel(grown, (x, y) => root.near(cut.px(x, y), clear.px(x, y), `no trace of the lower stroke at ${x},${y}`));
      root.eachPixel(r, (x, y) => root.near(cut.px(x, y), bare.px(x, y), `the fill left whole in the hole at ${x},${y}`));
      for (let line = 0; line < data.sw; line++) {
        const across = (band.vertical ? r.x : r.y) + band.fringe + line;
        const at = (t, scene) => band.vertical ? scene.px(across, t) : scene.px(t, across);
        const from = band.vertical ? r.y : r.x, to = from + (band.vertical ? r.height : r.width);
        band.ends.forEach((on, end) => {
          if (!on)
            return;
          const tip = end === 0 ? from : to;
          const outside = end === 0 ? tip - 1 : tip;
          root.near(at(outside, cut), at(outside, whole), `the stroke just outside the span's end ${end}, line ${line}`);
          verify(Math.abs(at(outside, whole).a - at(outside, clear).a) > 0.05 || Math.abs(at(outside, whole).r - at(outside, clear).r) > 0.05, `the stroke shows outside the span's end ${end}`);
          // what the lower stroke adds (A less A'): runs down to nothing
          // into the hole, with no pixel out of step
          const values = [];
          for (let t = tip - 3; t <= tip + 3; t++) {
            const a = at(t, cut), b = at(t, clear);
            values.push({
              "r": a.r - b.r,
              "g": a.g - b.g,
              "b": a.b - b.b,
              "a": a.a - b.a
            });
          }
          root.noSpike(values, `along the line at the span's end ${end}, line ${line}`);
        });
      }
    }
  }

  // The stub's corner under a wall, per device pixel (the logical-pixel rows
  // read the middle of a pixel and miss the wall's anti-aliased row at 1.25):
  // the cut scene equals the scene with the lower stroke transparent in the
  // corner piece's rect grown 2 px across
  function test_stub_corner_device_pixels_data() {
    const rows = [];
    for (const sw of [1, 2]) {
      for (const sa of [1, 0.5])
        rows.push({
          "tag": `stroke ${sw}, a_s ${sa}`,
          "sw": sw,
          "sa": sa
        });
    }
    return rows;
  }
  function test_stub_corner_device_pixels(data) {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    root.setStroke(data.sw);
    const c = root.joinCase("popout joined at an end to a pill bar's stub");
    const opts = {
      "w": c.w,
      "h": c.h
    };
    const cut = root.render(c.specs(data.sa, 1, true, true), opts);
    const clear = root.render(c.specs(data.sa, 1, false, true), opts);
    const r = c.bands[0].rect;
    let seen = 0;
    root.eachDevicePixel(Qt.rect(r.x, r.y - 2, r.width, r.height + 4), (xd, yd) => {
      seen++;
      root.near(cut.dpx(xd, yd), clear.dpx(xd, yd), `no trace of the lower stroke at device pixel ${xd},${yd}`);
    });
    verify(seen > 0);
  }

  // The must-not rows' "the stroke just outside the span's end", per device
  // pixel (that one reads a logical pixel's middle): every device pixel within
  // 2 px outside a tip, across the band's stroke lines, equals the scene with
  // no cut
  function test_ends_device_pixels_data() {
    return root.mustNotData().filter(d => d.fa === 1);
  }
  function test_ends_device_pixels(data) {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    root.setStroke(data.sw);
    const c = root.joinCase(data.name);
    const opts = {
      "w": c.w,
      "h": c.h
    };
    const cut = root.render(c.specs(data.sa, 1, true, true), opts);
    const whole = root.render(c.specs(data.sa, 1, true, false), opts);
    let seen = 0;
    for (const band of c.bands) {
      const r = band.rect;
      const a0 = (band.vertical ? r.x : r.y) + band.fringe;
      const from = band.vertical ? r.y : r.x, to = from + (band.vertical ? r.height : r.width);
      band.ends.forEach((on, end) => {
        if (!on)
          return;
        const tip = end === 0 ? from : to;
        // (each takes the pixel centred on the tip, at end 0 by a hair past the box's open end: half in the span, it is the lower copy's, Utils.tieInset)
        const along = end === 0 ? [tip - 2, tip + 1e-6] : [tip, tip + 2];
        const box = band.vertical ? Qt.rect(a0, along[0], data.sw, along[1] - along[0]) : Qt.rect(along[0], a0, along[1] - along[0], data.sw);
        root.eachDevicePixel(box, (xd, yd) => {
          seen++;
          root.near(cut.dpx(xd, yd), whole.dpx(xd, yd), `the stroke outside the span's end ${end} at device pixel ${xd},${yd}`);
        });
      });
    }
    verify(seen > 0);
  }

  // The hollow row's frame half: a tiled menu's tiles (rect copies, gaps
  // between them) over the frame's stroke, which runs on unbroken in the gaps
  function test_tiles_over_the_frame_data() {
    const rows = [];
    for (const sw of [1, 2]) {
      for (const fa of [0.8, 1])
        rows.push({
          "tag": `stroke ${sw}, fill ${fa}`,
          "sw": sw,
          "fa": fa
        });
    }
    return rows;
  }
  function test_tiles_over_the_frame(data) {
    root.needsGpuAtFractional();
    root.setStroke(data.sw);
    const frame = frameComp.createObject(sources);
    const edge = root.frameSpec(frame, {
      "c": root.blue.c,
      "a": data.fa
    }, root.line(1), []);
    const tile = x => ({
          "kind": "rect",
          "rank": "surface",
          "x": x,
          "y": 6,
          "w": 40,
          "h": 30,
          "radius": 4,
          "fill": root.solid
        });
    const alone = root.render([edge]);
    const tiled = root.render([edge, tile(20), tile(70)]);
    for (const x of [62, 65, 68])
      root.near(tiled.px(x, 9), alone.px(x, 9), `the line unbroken in the gap, x ${x}`);
    root.near(tiled.px(40, 9), root.filled(root.solid), "under a tile, the tile's value");
    verify(Math.abs(alone.px(65, 9).a - alone.px(65, 50).a) > 0.05 || Math.abs(alone.px(65, 9).r - alone.px(65, 50).r) > 0.05, "the frame's stroke shows");
  }

  // ---- a surface cut to its window (EdgePopout and the dock: blurClip) ----

  // A dock-like box whose copy is cut 20 px short of its end (its window's
  // edge): past the cut every pixel is the frame's alone (fill and stroke),
  // inside it the scene with no cut
  function test_cut_to_its_window_data() {
    const rows = [];
    for (const sw of [1, 2])
      rows.push({
        "tag": `stroke ${sw}`,
        "sw": sw
      });
    return rows;
  }
  function test_cut_to_its_window(data) {
    root.needsGpuAtFractional();
    root.setStroke(data.sw);
    const frame = frameComp.createObject(sources);
    const edge = root.frameSpec(frame, root.blue, root.line(1), []);
    const dock = root.placed({
      "boxWidth": 60,
      "boxHeight": 30
    }, 50, 10 - data.sw);
    root.settle([dock]);
    const box = root.attachedSpec(dock, "surface", root.green, root.line(1));
    const clipped = Object.assign({
      "clip": Qt.rect(0, 0, dock.x + 60 - 20, 100)
    }, box);
    const alone = root.render([edge]);
    const whole = root.render([edge, box]);
    const cut = root.render([edge, clipped]);
    root.eachPixel(Qt.rect(dock.x + 41, 0, 30, 60), (x, y) => root.near(cut.px(x, y), alone.px(x, y), `past the cut, the frame alone at ${x},${y}`));
    root.eachPixel(Qt.rect(0, 0, dock.x + 39, 60), (x, y) => root.near(cut.px(x, y), whole.px(x, y), `inside the cut, as uncut at ${x},${y}`));
  }

  // ---- the frame's corner arcs (FrameOutline) ----

  // Every device pixel whose centre falls in `box` (logical px)
  function eachDevicePixel(box, visit) {
    const first = v => Math.ceil(v * root.dpr - 0.5);
    for (let yd = first(box.y); (yd + 0.5) / root.dpr < box.y + box.height; yd++) {
      for (let xd = first(box.x); (xd + 0.5) / root.dpr < box.x + box.width; xd++)
        visit(xd, yd);
    }
  }

  // The frame's top-left corner box (8, 8, 10 x 10: radius 8, stroke 2) with
  // an opening along the top edge. Uncovered (it starts at 14, inside the
  // box, short of spanning it): the arc stays, as with no opening. Covered (it
  // starts at 8, the box's start): the box is left open, no arc. The left
  // stroke just below the box stays either way
  function test_frame_corners_data() {
    return [
      {
        "tag": "uncovered",
        "start": 14,
        "covered": false
      },
      {
        "tag": "covered",
        "start": 8,
        "covered": true
      }
    ];
  }
  function test_frame_corners(data) {
    root.needsGpuAtFractional();
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    root.setStroke(2);
    const frame = frameComp.createObject(sources);
    frame.radius = 8;
    const box = FrameOutline.cornerBox(frame.spec, true, true);
    const holes = [
      {
        "edge": "top",
        "start": data.start,
        "end": 60
      }
    ];
    const sceneOf = (stroke, h) => root.render([root.frameSpec(frame, root.blue, stroke, h)]);
    const plain = sceneOf(root.line(1), []);
    const bare = sceneOf(null, []);
    const opened = sceneOf(root.line(1), holes);
    let shows = false;
    root.eachDevicePixel(box, (xd, yd) => {
      const want = data.covered ? bare.dpx(xd, yd) : plain.dpx(xd, yd);
      root.near(opened.dpx(xd, yd), want, `the corner box, device pixel ${xd},${yd}`);
      if (Math.abs(plain.dpx(xd, yd).a - bare.dpx(xd, yd).a) > 0.05)
        shows = true;
    });
    verify(shows, "the no-opening scene's stroke shows in the box");
    root.near(opened.px(9, 25), plain.px(9, 25), "the left stroke below the box");
  }

  // Main's own stroke pieces over black, each at the device px its window
  // shows on: every strip's stroke Rectangle (non-anti-aliased, in the
  // strip's window at BorderPanel's place) and every corner's CornerPiece
  // (in its window's rounded box), the corners over the strips
  Component {
    id: mainSceneComp

    Item {
      id: mainScene
      property var spec
      property color strokeColor
      width: 160
      height: 100
      Rectangle {
        anchors.fill: parent
        color: "black"
      }
      Repeater {
        model: root.strips(mainScene.spec.innerLeft)

        delegate: Item {
          id: strip
          required property var modelData
          readonly property rect stroke: FrameOutline.stripStroke(strip.modelData.edge, strip.modelData.length, mainScene.spec.innerLeft, mainScene.spec.innerBorderRadius, mainScene.spec.strokeWidth)
          x: Math.round(root.dpr * strip.modelData.origin.x) / root.dpr
          y: Math.round(root.dpr * strip.modelData.origin.y) / root.dpr
          // A pixel is filled when its centre is in [start, end) on the
          // compositor's GPU; the grab's rasterizer breaks a tie in y the
          // other way (a flipped target), so the rect sits a hundredth of a
          // device px early: a centre on its start is in, on its end out,
          // whichever rasterizer
          Rectangle {
            x: strip.stroke.x - 0.01 / root.dpr
            y: strip.stroke.y - 0.01 / root.dpr
            width: strip.stroke.width
            height: strip.stroke.height
            color: mainScene.strokeColor
          }
        }
      }
      Repeater {
        model: FrameOutline.corners

        delegate: Item {
          id: cornerWindow
          required property var modelData
          readonly property rect box: FrameOutline.cornerBox(mainScene.spec, cornerWindow.modelData.isLeft, cornerWindow.modelData.isTop)
          x: Math.round(root.dpr * cornerWindow.box.x) / root.dpr
          y: Math.round(root.dpr * cornerWindow.box.y) / root.dpr
          width: Math.round(root.dpr * cornerWindow.box.width) / root.dpr
          height: Math.round(root.dpr * cornerWindow.box.height) / root.dpr
          clip: true
          Item {
            width: cornerWindow.box.width
            height: cornerWindow.box.height
            CornerPiece {
              borderRadius: mainScene.spec.innerBorderRadius
              strokeWidth: mainScene.spec.strokeWidth
              fillColor: "transparent"
              strokeColor: mainScene.strokeColor
              isLeft: cornerWindow.modelData.isLeft
              isTop: cornerWindow.modelData.isTop
            }
          }
        }
      }
    }
  }
  // The frame copy's stroke is main's: the same pixels as the strips'
  // Rectangles and the corner pieces over black, along every edge's stroke
  // and round each corner's box (grown 2 px). The live case, radius 6 inset
  // 8 (stroke 2), puts the strokes and the corner box on half device px at
  // 1.25. At radius 0 the corner piece is 2 px, 2.5 device px at 1.25, so
  // its arm and its stroke's inner side end on a device pixel's centre in a
  // window on whole device px; the grab breaks that tie differently in two
  // equal trees, so radius 0's corners are read at scale 1 here and at 1.25
  // live (`fractionalCorners`)
  function test_frame_stroke_is_mains_data() {
    return [
      {
        "tag": "radius 6 inset 8",
        "radius": 6,
        "inset": 8,
        "fractionalCorners": true
      },
      {
        "tag": "radius 6 inset 7.6 (every corner window on whole device px at 1.25)",
        "radius": 6,
        "inset": 7.6,
        "fractionalCorners": true
      },
      {
        "tag": "radius 2 inset 8",
        "radius": 2,
        "inset": 8,
        "fractionalCorners": true
      },
      {
        "tag": "radius 0 inset 8",
        "radius": 0,
        "inset": 8,
        "fractionalCorners": false
      },
      {
        "tag": "radius 1 inset 10",
        "radius": 1,
        "inset": 10,
        "fractionalCorners": true
      }
    ];
  }
  function test_frame_stroke_is_mains(data) {
    root.needsGpuAtFractional();
    root.setStroke(2);
    const frame = frameComp.createObject(sources);
    frame.radius = data.radius;
    frame.inset = data.inset;
    const stroke = root.line(1);
    const frameScene = root.render([root.frameSpec(frame, {
        "c": root.blue.c,
        "a": 0
      }, stroke, [])]);
    const mainScene = createTemporaryObject(mainSceneComp, root, {
      "spec": frame.spec,
      "strokeColor": root.strokeColor(stroke)
    });
    waitForRendering(mainScene);
    const main = grabImage(mainScene);
    const n = data.inset + 2;
    const grown = c => {
      const box = FrameOutline.cornerBox(frame.spec, c.isLeft, c.isTop);
      return Qt.rect(box.x - 2, box.y - 2, box.width + 4, box.height + 4);
    };
    const regions = [
      {
        "what": "top",
        "rect": Qt.rect(80, 0, 1, n)
      },
      {
        "what": "bottom",
        "rect": Qt.rect(80, 100 - n, 1, n)
      },
      {
        "what": "left",
        "rect": Qt.rect(0, 50, n, 1)
      },
      {
        "what": "right",
        "rect": Qt.rect(160 - n, 50, n, 1)
      }
    ].concat(root.dpr === 1 || data.fractionalCorners ? FrameOutline.corners.map(c => ({
          "what": `corner ${c.isTop ? "top" : "bottom"}-${c.isLeft ? "left" : "right"}`,
          "rect": grown(c)
        })) : []);
    for (const region of regions) {
      let seen = 0;
      root.eachDevicePixel(region.rect, (xd, yd) => {
        seen++;
        const got = frameScene.dpx(xd, yd);
        const want = {
          "r": main.red(xd, yd) / 255,
          "g": main.green(xd, yd) / 255,
          "b": main.blue(xd, yd) / 255
        };
        for (const k of ["r", "g", "b"])
          verify(root.levels(got[k] - want[k]) <= root.tol, `${region.what}, device pixel ${xd},${yd}: ${k} ${got[k].toFixed(4)} (frame copy) vs ${want[k].toFixed(4)} (main's pieces)`);
      });
      verify(seen > 0, `no device pixel in ${region.what}`);
    }
  }

  // ---- a fill's anti-aliased edge, and a non-whole logical size ----

  // A fill's edge half covering a pixel (c_f 0.5) over a lower fill: both
  // captures read the mean of the two fills' values
  function test_aa_edge_over_a_lower_fill() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const lower = {
      "kind": "rect",
      "rank": "bar",
      "x": 10,
      "y": 10,
      "w": 100,
      "h": 60,
      "fill": root.blue
    };
    const upper = {
      "kind": "rect",
      "rank": "surface",
      "x": 40.5,
      "y": 20,
      "w": 40,
      "h": 30,
      "radius": 4,
      "fill": root.green
    };
    const px = root.render([lower, upper]);
    const a = root.filled(root.blue), b = root.filled(root.green);
    const mean = {
      "r": (a.r + b.r) / 2,
      "g": (a.g + b.g) / 2,
      "b": (a.b + b.b) / 2,
      "a": (a.a + b.a) / 2
    };
    root.near(px.px(40, 30), mean, "the edge pixel, half each");
    root.near(px.px(39, 30), a, "left of it, the lower fill");
    root.near(px.px(41, 30), b, "right of it, the upper fill");
  }

  // A logical size that isn't whole (399.2 x 299.2: 499 x 374 device px, as a real output's logical size at 1.25), a 1-px feature at a
  // device position that isn't whole in logical px: the composite samples
  // 1:1, so the device pixel holds the feature and its neighbours nothing
  function test_non_whole_logical_size() {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    if (!root.gpu)
      skip("software scene graph: the composite is read through the real shader only");
    const line = (x, y, w, h) => ({
          "kind": "rect",
          "rank": "bar",
          "x": x,
          "y": y,
          "w": w,
          "h": h,
          "fill": root.solid
        });
    // 0.8 logical px = 1 device px, at device x 376 and device y 251
    const px = root.render([line(300.8, 20, 0.8, 200), line(20, 200.8, 300, 0.8)], {
      "w": 399.2,
      "h": 299.2
    });
    const full = root.filled(root.solid);
    const nothing = {
      "r": 0,
      "g": 0,
      "b": 0,
      "a": 0
    };
    root.near(px.dpx(376, 100), full, "the vertical line's device pixel");
    root.near(px.dpx(375, 100), nothing, "its left neighbour");
    root.near(px.dpx(377, 100), nothing, "its right neighbour");
    root.near(px.dpx(100, 251), full, "the horizontal line's device pixel");
    root.near(px.dpx(100, 250), nothing, "its upper neighbour");
    root.near(px.dpx(100, 252), nothing, "its lower neighbour");
  }

  // A straight wall whose stroke edge lands on a device pixel's centre draws its width, as one that doesn't (the CurveRenderer tie, Utils.tieInset)
  function test_stroke_width_on_a_pixel_centre_data() {
    return [
      {
        "tag": "stroke 2",
        "sw": 2
      },
      {
        "tag": "stroke 1",
        "sw": 1
      }
    ];
  }
  function test_stroke_width_on_a_pixel_centre(data) {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    root.needsGpuAtFractional();
    root.setStroke(data.sw);
    const src = root.placed({
      "boxWidth": 61,
      "boxHeight": 40
    }, 0, 5);
    root.settle([src]);
    src.x = 21 - src.boxRect.x;
    const left = src.x + src.boxRect.x, right = left + src.boxRect.width;
    compare(right * 1.25 % 1, 0.5, "the right wall's outer edge is on a device pixel's centre");
    const px = root.render([root.attachedSpec(src, "surface", {
        "c": Qt.rgba(0, 0, 0, 1),
        "a": 0
      }, root.line(1))]);
    const top = src.y + src.boxRect.y + src.filletRadius + 3, bottom = src.y + src.boxRect.y + src.boxRect.height - src.filletRadius - 3;
    for (const wall of [left, right - data.sw]) {
      for (let yd = Math.ceil(top * 1.25); yd < bottom * 1.25; yd++) {
        let sum = 0;
        for (let xd = Math.floor((wall - 1) * 1.25); xd < Math.ceil((wall + data.sw + 1) * 1.25); xd++)
          sum += px.dpx(xd, yd).r / 0.9;
        verify(Math.abs(sum - data.sw * 1.25) <= 0.1, `wall at ${wall}, device row ${yd}: drawn ${sum.toFixed(3)} device px wide, not ${data.sw * 1.25}`);
      }
    }
  }

  // A popout flush on a pill (or island) stretched to its box, its walls starting at the band's top as t2's do on Hyprland: each wall draws the same width on every device row, the pill's, the band's and the popout's (the band runs a pixel past a wall it reaches, EdgeAttach.strokeHoleAlong; a copy's clip keeps its wall's fringe, SlideAnimation.startOverflow)
  function test_flush_walls_device_pixels_data() {
    return [
      {
        "tag": "pill, stroke 2",
        "kind": "pill",
        "sw": 2,
        "left": 23,
        "w": 63
      },
      {
        "tag": "pill, stroke 1",
        "kind": "pill",
        "sw": 1,
        "left": 23,
        "w": 63
      },
      {
        "tag": "pill, stroke 2, start wall on a tie",
        "kind": "pill",
        "sw": 2,
        "left": 22,
        "w": 61
      },
      {
        "tag": "island, stroke 2",
        "kind": "island",
        "sw": 2,
        "left": 22,
        "w": 61
      }
    ];
  }
  function test_flush_walls_device_pixels(data) {
    if (root.dpr !== 1.25)
      skip("scale 1.25 row");
    root.needsGpuAtFractional();
    root.setStroke(data.sw);
    const black = {
      "c": Qt.rgba(0, 0, 0, 1),
      "a": 0
    };
    let pop, lower, top;
    if (data.kind === "pill") {
      const pill = root.placed({
        "boxWidth": data.w,
        "boxHeight": 18,
        "startCornerRadius": 0,
        "endCornerRadius": 0
      }, 0, 4);
      const across = EdgeAttach.strokeHoleAcross(pill.farV - pill.half, pill.strokeWidth);
      pop = root.placed({
        "boxWidth": data.w,
        "boxHeight": 40,
        "flushStart": true,
        "flushEnd": true
      }, 0, 4 + across.start);
      root.settle([pill, pop]);
      pill.x = data.left - pill.boxRect.x;
      pop.x = data.left - pop.boxRect.x;
      const along = EdgeAttach.strokeHoleAlong(pop.x + pop.coverStart - pill.x, pop.x + pop.coverEnd - pill.x, pill.startMargin, pill.alongLength - pill.endMargin);
      lower = root.attachedSpec(pill, "bar", black, root.line(1), [pill._rectFrom(along.start, across.start, along.end - along.start, across.size)]);
      top = pill.y + pill.boxRect.y + pill.filletRadius + 3;
    } else {
      const iy = 4, ih = 18;
      const across = EdgeAttach.strokeHoleAcross(ih - data.sw, data.sw);
      pop = root.placed({
        "boxWidth": data.w,
        "boxHeight": 40,
        "flushStart": true,
        "flushEnd": true
      }, 0, iy + across.start);
      root.settle([pop]);
      pop.x = data.left - pop.boxRect.x;
      const along = EdgeAttach.strokeHoleAlong(0, data.w, 0, data.w);
      lower = {
        "kind": "rect",
        "rank": "bar",
        "x": data.left,
        "y": iy,
        "w": data.w,
        "h": ih,
        "fill": {
          "c": Qt.rgba(0, 0, 0, 1),
          "a": 1
        },
        "stroke": root.line(1),
        "holes": [Qt.rect(along.start, across.start, along.end - along.start, across.size)]
      };
      top = iy + across.start;
    }
    const px = root.render([lower, root.attachedSpec(pop, "surface", black, root.line(1))], {
      "w": 120,
      "h": 80
    });
    const bottom = pop.y + pop.boxRect.y + pop.boxRect.height - pop.filletRadius - 3;
    for (const wall of [data.left, data.left + data.w - data.sw]) {
      const sumAt = yd => {
        let sum = 0;
        for (let xd = Math.floor((wall - 1) * 1.25); xd < Math.ceil((wall + data.sw + 1) * 1.25); xd++)
          sum += px.dpx(xd, yd).r / 0.9;
        return sum;
      };
      const ref = sumAt(Math.floor(bottom * 1.25) - 1);
      for (let yd = Math.ceil(top * 1.25); yd < bottom * 1.25; yd++) {
        const sum = sumAt(yd);
        verify(Math.abs(sum - ref) <= 0.05, `${data.kind} wall at ${wall}, device row ${yd}: drawn ${sum.toFixed(3)} device px wide, ${ref.toFixed(3)} below the band`);
      }
    }
  }

  // ---- a detached box (diag-live-1 F11) ----

  // A detached box (a free menu, a detached popout) in the real copy: its
  // box keeps its own rect inside the surface at any offset. Four stroke runs
  // at the box's edges, four round corners, nothing drawn outside the box,
  // right and bottom included
  function detachedCase() {
    const src = root.placed({
      "detached": true,
      "detachedOffset": 10,
      "boxWidth": 60,
      "boxHeight": 40
    }, 20, 10);
    root.settle([src]);
    const b = src.boxRect;
    verify(b.x > 0 && b.y > 0, "the box is offset in its surface");
    return {
      "src": src,
      "box": Qt.rect(src.x + b.x, src.y + b.y, b.width, b.height)
    };
  }

  function test_detached_box_chrome() {
    root.needsGpuAtFractional();
    root.setStroke(2);
    const c = root.detachedCase();
    const px = root.render([root.attachedSpec(c.src, "surface", root.solid, root.line(1))]);
    const box = c.box, line = root.over(root.line(1), root.filled(root.solid));
    const mid = Math.floor(box.x + box.width / 2), midY = Math.floor(box.y + box.height / 2);
    root.near(px.px(mid, box.y), line, "the top run");
    root.near(px.px(mid, box.y + box.height - 1), line, "the bottom run");
    // (the stroke's second column: its outer one half-covers a device pixel at 1.25)
    root.near(px.px(box.x + 1, midY), line, "the left run");
    root.near(px.px(box.x + box.width - 1, midY), line, "the right run");
    root.near(px.px(mid, midY), root.filled(root.solid), "the fill");
    const clear = {
      "r": 0,
      "g": 0,
      "b": 0,
      "a": 0
    };
    for (const corner of [[box.x, box.y], [box.x + box.width - 1, box.y], [box.x, box.y + box.height - 1], [box.x + box.width - 1, box.y + box.height - 1]])
      root.near(px.px(corner[0], corner[1]), clear, `the round corner at ${corner}`);
    const item = Qt.rect(c.src.x, c.src.y, c.src.width, c.src.height);
    root.eachPixel(item, (x, y) => {
      // (a pixel's grace round the box: its edge may fall inside a device pixel at 1.25)
      if (x < box.x - 1 || x >= box.x + box.width + 1 || y < box.y - 1 || y >= box.y + box.height + 1)
        root.near(px.px(x, y), clear, `nothing outside the box at ${x},${y}`);
    });
  }

  // The same shape the shadow casts from: the outline copy is the box's
  // silhouette, black on white here
  function test_detached_box_outline() {
    root.needsGpuAtFractional();
    root.setStroke(2);
    const c = root.detachedCase();
    const layer = createTemporaryObject(layerComp, root, {
      "width": 160,
      "height": 100,
      "draws": "outline",
      "backColor": "white"
    });
    layer.shapes = [root.shapeFor(root.attachedSpec(c.src, "surface", root.solid, root.line(1)), layer)];
    waitForRendering(layer);
    const img = grabImage(layer);
    const at = v => Math.floor((v + 0.5) * root.dpr);
    const dark = (x, y) => img.red(at(x), at(y)) < 20;
    const box = c.box;
    const midY = Math.floor(box.y + box.height / 2), mid = Math.floor(box.x + box.width / 2);
    verify(dark(mid, midY), "the silhouette is the box");
    verify(dark(box.x + box.width - 1, midY), "its right edge");
    verify(dark(mid, box.y + box.height - 1), "its bottom edge");
    verify(!dark(box.x + box.width, midY), "nothing past the right edge");
    verify(!dark(mid, box.y + box.height), "nothing past the bottom edge");
    verify(!dark(box.x, box.y), "a round corner");
    verify(!dark(box.x + box.width - 1, box.y + box.height - 1), "a round corner at the far end");
  }

  // The detached box with a hole in its side (a submenu on it): the pieces'
  // Loaders keep the box's rect too
  function test_detached_box_with_a_hole() {
    if (!root.gpu)
      skip("software scene graph: a clipped Shape is drawn wrong (run under xvfb with llvmpipe)");
    root.setStroke(2);
    const c = root.detachedCase();
    const box = c.box, b = c.src.boxRect;
    const edge = EdgeAttach.strokeHoleAcross(b.x + b.width - 2, 2);
    const hole = Qt.rect(edge.start, b.y + 12, edge.size, 14);
    const cut = root.render([root.attachedSpec(c.src, "surface", root.solid, root.line(1), [hole])]);
    const clear = root.render([root.attachedSpec(c.src, "surface", root.solid, null, [hole])]);
    const whole = root.render([root.attachedSpec(c.src, "surface", root.solid, root.line(1))]);
    const right = box.x + box.width - 1;
    const inHole = Math.floor(box.y + 12 + 7);
    root.near(cut.px(right, inHole), clear.px(right, inHole), "no stroke in the hole");
    root.near(cut.px(right, Math.floor(box.y + 6)), whole.px(right, Math.floor(box.y + 6)), "the right run above the hole");
    root.near(cut.px(right, Math.floor(box.y + 34)), whole.px(right, Math.floor(box.y + 34)), "the right run below the hole");
    const line = root.over(root.line(1), root.filled(root.solid));
    root.near(cut.px(Math.floor(box.x + box.width / 2), box.y + box.height - 1), line, "the bottom run");
    root.near(cut.px(box.x + 1, Math.floor(box.y + box.height / 2)), line, "the left run");
  }

  // ---- a box sliding in over the bars: drawn by itself over them, by the backing window past them ----

  // A surface over a backdrop that reads as black or white (its grab's
  // premultiplied colour and alpha, as the scene's two captures are read)
  Component {
    id: holderComp

    Item {
      property color back: "black"

      Rectangle {
        anchors.fill: parent
        color: parent.back
      }
    }
  }

  // A detached box sliding in from the bottom over a band of the screen
  // (the bars, from the line F down), at three places: wholly in the band,
  // across F, wholly past it. The box's part in the band is the surface's
  // own (ownFillRect), the rest its copy's (BlurShape.fillClip); the two over
  // each other at F and on either side of it hold the box's fill and its
  // side strokes as at rest: no seam, no double, no gap
  function test_split_over_bars_data() {
    return [
      {
        "tag": "wholly in the band",
        "top": 84
      },
      {
        "tag": "across the line",
        "top": 76
      },
      {
        "tag": "wholly past the line",
        "top": 40
      }
    ];
  }

  function test_split_over_bars(data) {
    root.needsGpuAtFractional();
    root.setStroke(2);
    const lineY = 80;
    const fill = root.blue;
    const stroke = root.line(1);
    // (beside the copy's scene: a grab reads the window)
    const holder = createTemporaryObject(holderComp, root, {
      "x": 200,
      "width": 160,
      "height": 100
    });
    const src = createTemporaryObject(surfaceComp, holder, {
      "edge": ScreenEdge.Bottom,
      "detached": true,
      "detachedOffset": 10,
      "boxWidth": 60,
      "boxHeight": 16,
      "backed": true,
      "fillColor": root.fillColor(fill),
      "strokeColor": root.strokeColor(stroke)
    });
    root.settle([src]);
    // (the box on whole device pixels at 1.25)
    src.x = 56 - src.boxRect.x;
    src.y = data.top - src.boxRect.y;
    src.ownFillRect = {
      "x": -src.x,
      "y": lineY - src.y,
      "width": 160,
      "height": 100 - lineY
    };
    const box = Qt.rect(src.x + src.boxRect.x, src.y + src.boxRect.y, src.boxRect.width, src.boxRect.height);
    const copy = root.render([Object.assign(root.attachedSpec(src, "surface", fill, stroke), {
        "fillClip": Qt.rect(0, 0, 160, lineY)
      })]);
    const mid = Math.floor(box.x + box.width / 2);
    const rows = [box.y + 3, lineY - 1, lineY, lineY + 1, box.y + box.height - 4].filter(y => y >= box.y + 3 && y < box.y + box.height - 3);
    verify(rows.length >= 2, "rows inside the box");
    const outside = [lineY - 1, lineY, lineY + 1].filter(y => y >= box.y && y < box.y + box.height);
    // The surface's own part, over black and over white, read at once (a
    // grab is not kept apart from the next)
    const at = v => Math.floor((v + 0.5) * root.dpr);
    const own = root.grabPremultiplied(holder);
    // The surface over its copy, as the layers stack
    const seen = (x, y) => {
      const o = own(at(x), at(y));
      const c = copy.px(x, y);
      return {
        "r": o.r + (1 - o.a) * c.r,
        "g": o.g + (1 - o.a) * c.g,
        "b": o.b + (1 - o.a) * c.b,
        "a": o.a + (1 - o.a) * c.a
      };
    };
    for (const y of rows) {
      root.near(seen(mid, y), root.filled(fill), `the fill at ${y}`);
      root.near(seen(box.x + 1, y), root.over(stroke, root.filled(fill)), `the left run at ${y}`);
      root.near(seen(box.x + box.width - 2, y), root.over(stroke, root.filled(fill)), `the right run at ${y}`);
    }
    const clear = {
      "r": 0,
      "g": 0,
      "b": 0,
      "a": 0
    };
    for (const y of outside) {
      root.near(seen(box.x - 3, y), clear, `nothing past the left side at ${y}`);
      root.near(seen(box.x + box.width + 2, y), clear, `nothing past the right side at ${y}`);
    }
  }

  // ---- a copy reads its source's paths ----

  function test_copy_paths_are_the_sources_data() {
    return [
      {
        "tag": "plain",
        "props": {}
      },
      {
        "tag": "joined",
        "props": {
          "joinStart": true,
          "joinEnd": true,
          "flushStart": true
        }
      },
      {
        "tag": "straight",
        "props": {
          "straight": true,
          "startCornerRadius": 6
        }
      },
      {
        "tag": "detached",
        "props": {
          "detached": true,
          "detachedOffset": 10
        }
      }
    ];
  }

  function test_copy_paths_are_the_sources(data) {
    const src = root.surface(data.props);
    root.settle([src]);
    const copy = createTemporaryObject(copyComp, sources, {
      "source": src
    });
    verify(src.fillPath.length > 0 && src.strokePath.length > 0, "the source has paths");
    compare(copy.fillPath, src.fillPath);
    compare(copy.strokePath, src.strokePath);
    compare(SurfaceOutline.fillPath(copy._spec, copy._m, copy.width, copy.height), src.fillPath, "its own derivation is the source's");
    compare(SurfaceOutline.strokePath(copy._spec, copy._m, copy.width, copy.height), src.strokePath, "its own derivation is the source's");
  }
}
