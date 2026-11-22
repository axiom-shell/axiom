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
  readonly property real tol: 2 / 255

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

  // One chrome capture: the real `Copies` of `shapes` (and `erasers`), over
  // black when read as pixels in software
  Component {
    id: layerComp

    Item {
      id: layer
      property var shapes: []
      property var erasers: []
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
        erasers: layer.erasers
        draws: layer.draws
        asAlpha: layer.asAlpha
      }
    }
  }

  // The scene: both captures of `shapes`/`erasers` and, where the scene graph
  // is GPU-backed, the real ChromeComposite over `back`. The two
  // `ShaderEffectSource`s are written as BlurBackingWindow.qml:207-224 has
  // them: harness plumbing, not a second rule. Without a GPU the layers sit
  // one over the other, each grabbed over black.
  Component {
    id: sceneComp

    Item {
      id: scene
      property var shapes: []
      property var erasers: []
      property color back: "black"
      property real lw: 160
      property real lh: 100
      readonly property Item colorLayer: colorLoader.item
      readonly property Item alphaLayer: alphaLoader.item
      readonly property Item hold: hold
      width: scene.lw
      height: scene.lh

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
          item.erasers = Qt.binding(() => scene.erasers);
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
          item.erasers = Qt.binding(() => scene.erasers);
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

  // The real BlurShape of `spec` { kind, level, src | w, h, radius, bw,
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
    return shapeComp.createObject(scene, {
      "source": source,
      "kind": spec.kind,
      "color": root.fillColor(spec.fill ?? {
        "c": Qt.rgba(0, 0, 0, 1),
        "a": 0
      }),
      "strokeColor": root.strokeColor(spec.stroke),
      "paintLevel": PaintOrder.of(spec.level),
      "x": spec.x ?? 0,
      "y": spec.y ?? 0,
      "clipRect": spec.clip ?? null
    });
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

  // The composite of `scene` as { px(x, y) -> { r, g, b, a } (premultiplied, 0-1), dpx(xd, yd) the same at a device
  // pixel }, x and y logical, read at the middle of their pixel
  function capture(scene) {
    const at = v => Math.floor((v + 0.5) * root.dpr);
    let grab;
    if (root.gpu) {
      scene.back = "black";
      waitForRendering(scene);
      const onBlack = grabImage(scene);
      scene.back = "white";
      waitForRendering(scene);
      const onWhite = grabImage(scene);
      grab = (xd, yd) => ({
            "r": onBlack.red(xd, yd) / 255,
            "g": onBlack.green(xd, yd) / 255,
            "b": onBlack.blue(xd, yd) / 255,
            // (over white, a pixel is rgb + (1 - a))
            "a": 1 - (onWhite.red(xd, yd) - onBlack.red(xd, yd)) / 255
          });
    } else {
      // (each capture a layer of its own, apart from the scene: a grab of the
      // scene's two layers returns the first twice here)
      const layer = asAlpha => createTemporaryObject(layerComp, root, {
          "width": scene.width,
          "height": scene.height,
          "shapes": scene.shapes,
          "erasers": scene.erasers,
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

  function near(got, want, what) {
    for (const k of ["r", "g", "b", "a"])
      verify(Math.abs(got[k] - want[k]) <= root.tol, `${what}: ${k} ${got[k].toFixed(4)} vs ${want[k].toFixed(4)}`);
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
        "level": "bar",
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
      "level": "bar",
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
      "level": "surface",
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

  // The order the shapes are registered in decides nothing: the level does
  function test_levels_not_registration() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    root.setStroke(2);
    const bar = {
      "kind": "rect",
      "level": "base",
      "x": 10,
      "y": 10,
      "w": 100,
      "h": 30,
      "fill": root.blue
    };
    // A solid bar's inner stroke: a stroke-only rect over its fill
    const stroke = {
      "kind": "rect",
      "level": "frame",
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

  // A toast card (level toast, its own border) over a dock's copy (level surface), in both orders
  function test_toast_over_dock() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const dock = {
      "kind": "attached",
      "level": "surface",
      "src": root.surface(),
      "x": 10,
      "y": 5,
      "fill": root.blue,
      "stroke": root.line(1)
    };
    const card = {
      "kind": "rect",
      "level": "toast",
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
          "level": "bar",
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
        if (Math.max(Math.abs(c.r - w.r), Math.abs(c.g - w.g), Math.abs(c.b - w.b), Math.abs(c.a - w.a)) > 1 / 255)
          off++;
      }
    }
    verify(count > 1000);
    compare(off, 0, `${off} of ${count} pixels differ from the scene with no holes (scale ${root.dpr})`);
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
          "level": "bar",
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
        if (Math.max(Math.abs(c.r - w.r), Math.abs(c.g - w.g), Math.abs(c.b - w.b), Math.abs(c.a - w.a)) > 1 / 255) {
          off++;
          if (first.length < 8)
            first.push(`${xd},${yd} (a ${c.a.toFixed(3)} vs ${w.a.toFixed(3)}, r ${c.r.toFixed(3)} vs ${w.r.toFixed(3)})`);
        }
      }
    }
    verify(count > 1000);
    // (S2-u2 confirmed: the stack's review expects this to fail until the pieces are placed on device pixels)
    expectFail("", "a device pixel outside the holes differs from the no-hole scene under a fractional copy origin");
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
          "level": "surface",
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
      "level": "bar",
      "src": src,
      "x": 10,
      "y": 5,
      "fill": fill,
      "stroke": root.line(1)
    };
    const tile = x => ({
          "kind": "rect",
          "level": "surface",
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

  // ---- live erasing (C16's Copies half) ----

  // The slots of `copies` (a Repeater's items: those with a `key`)
  function slotsOf(copies) {
    return Array.from(copies.children).filter(item => item.key !== undefined);
  }
  function slotOf(copies, shape) {
    return root.slotsOf(copies).find(item => item.key === String(shape.uid)) ?? null;
  }

  // A shape moves from `shapes` to `erasers` and back: its slot stays (one
  // object, the same count); while erasing, where it stood is (0,0,0,0) over a
  // lower shape's fill and stroke (erased half a level under, its stroke not
  // drawn), and a shape at its own level keeps the window's own
  function test_erasing_moves_not_remakes() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    root.setStroke(2);
    const lower = {
      "kind": "rect",
      "level": "bar",
      "x": 10,
      "y": 10,
      "w": 80,
      "h": 50,
      "fill": root.green,
      "stroke": root.line(1)
    };
    const mover = {
      "kind": "rect",
      "level": "surface",
      "x": 40,
      "y": 5,
      "w": 40,
      "h": 30,
      "fill": root.blue,
      "stroke": root.line(1)
    };
    const peer = {
      "kind": "rect",
      "level": "surface",
      "x": 60,
      "y": 20,
      "w": 40,
      "h": 30,
      "fill": root.solid
    };
    const scene = root.makeScene([lower, mover, peer]);
    const [low, move, other] = scene.shapes;
    const copies = scene.colorLayer.copies;
    const count = root.slotsOf(copies).length;
    const slot = root.slotOf(copies, move);
    verify(slot !== null);
    compare(count, 3);
    const nothing = {
      "r": 0,
      "g": 0,
      "b": 0,
      "a": 0
    };
    const before = root.capture(scene);
    root.near(before.px(50, 20), root.filled(root.blue), "drawn: the mover's fill over the lower shape");
    root.near(before.px(50, 10), root.filled(root.blue), "drawn: over the lower stroke");
    root.near(before.px(41, 20), root.over(root.line(1), root.filled(root.blue)), "drawn: the mover's stroke");
    // (BlurBacking's order, one list per step: the overlay's shapes join
    // `erasers` while still drawn, then leave `shapes`)
    scene.erasers = [move];
    compare(root.slotsOf(copies).length, count);
    verify(root.slotOf(copies, move) === slot, "the same slot with it in both lists");
    verify(!slot.erasing);
    const both = root.capture(scene);
    for (const p of [[50, 20], [50, 10], [41, 20], [70, 30], [20, 20]])
      root.near(both.px(p[0], p[1]), before.px(p[0], p[1]), `in both lists as it was at ${p}`);
    scene.shapes = [low, other];
    const erased = root.capture(scene);
    compare(root.slotsOf(copies).length, count);
    verify(root.slotOf(copies, move) === slot, "the same slot");
    verify(slot.erasing);
    root.near(erased.px(50, 20), nothing, "erased over the lower fill");
    root.near(erased.px(50, 10), nothing, "erased over the lower stroke");
    root.near(erased.px(41, 20), nothing, "the mover's stroke is not drawn");
    root.near(erased.px(70, 30), root.filled(root.solid), "a shape at the mover's level keeps the window's own");
    root.near(erased.px(20, 20), root.filled(root.green), "the lower fill outside it");
    root.near(erased.px(20, 10), root.over(root.line(1), root.filled(root.green)), "the lower stroke outside it");
    scene.shapes = [low, move, other];
    compare(root.slotsOf(copies).length, count);
    verify(root.slotOf(copies, move) === slot, "the same slot back in shapes");
    verify(!slot.erasing);
    const back = root.capture(scene);
    for (const p of [[50, 20], [50, 10], [41, 20], [70, 30], [20, 20]])
      root.near(back.px(p[0], p[1]), before.px(p[0], p[1]), `drawn again as it was at ${p}`);
    scene.erasers = [];
    const after = root.capture(scene);
    compare(root.slotsOf(copies).length, count);
    verify(root.slotOf(copies, move) === slot, "the same slot after");
    verify(!slot.erasing);
    for (const p of [[50, 20], [50, 10], [41, 20], [70, 30], [20, 20]])
      root.near(after.px(p[0], p[1]), before.px(p[0], p[1]), `back as it was at ${p}`);
  }

  // ---- the must-not rows (PX-7 rejected, D45, R50) ----

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
  function attachedSpec(src, level, fill, stroke, holes) {
    return {
      "kind": "attached",
      "level": level,
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
      const hole = pill._rectFrom(pop.x + pop.coverStart - pill.x, across.start, pop.coverLength, across.size);
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
      const win = Qt.rect(across.start, sub.y + sub.coverStart, across.size, sub.coverLength);
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
      const start = pop.x + pop.coverStart, length = pop.coverLength;
      // the inner-stroke rect's own coordinates (BarContainer.solidStroke)
      const hole = Qt.rect(start, 0, length, sw);
      return {
        "w": 180,
        "h": 110,
        "specs": (sa, fa, stroke, cut) => [
            {
              "kind": "rect",
              "level": "base",
              "x": 0,
              "y": 0,
              "w": 180,
              "h": 16,
              "fill": fills(fa).low
            },
            {
              "kind": "rect",
              "level": "frame",
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
        "specs": (sa, fa, stroke, cut) => [root.attachedSpec(left, "bar", fills(fa).low, stroke ? root.line(sa) : null, cut ? [hole] : []), root.attachedSpec(top, "merge", fills(fa).up, root.line(sa))],
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
      // (the band RoundedBorders.strokeHoles cuts: EdgeAttach.strokeHoleAcross)
      const edge = EdgeAttach.strokeHoleAcross(m - sw, sw);
      const band = Qt.rect(dock.x + dock.coverStart, edge.start, dock.coverLength, edge.size);
      return {
        "w": 160,
        "h": 100,
        "specs": (sa, fa, stroke, cut) => [root.frameSpec(frame, fills(fa).low, stroke ? root.line(sa) : null, cut ? [band] : []), root.attachedSpec(dock, "surface", fills(fa).up, root.line(sa))],
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
    const top = Qt.rect(pill.x + pill.coverStart, edge.start, pill.coverLength, edge.size);
    const side = Qt.rect(edge.start, m + 1, edge.size, Math.floor(m - sw + pill.joinCover) - (m + 1));
    return {
      "w": 160,
      "h": 100,
      "specs": (sa, fa, stroke, cut) => [root.frameSpec(frame, fills(fa).low, stroke ? root.line(sa) : null, cut ? [top, side] : []), root.attachedSpec(pill, "surface", fills(fa).up, root.line(sa))],
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

  // The frame's fixture source (RoundedBorders' contract: `strokeWidth`,
  // `strokeHoles`, `framePath`, `innerPath`), literal for the 160 x 100 screen
  // with a sharp 10 px border: the stroke along the inner edge, inside the frame
  Component {
    id: frameComp

    Item {
      readonly property real strokeWidth: Appearance.borderWidth
      property var strokeHoles: []
      readonly property var strokePaths: ({
          "1": "M 9.5 9.5 H 150.5 V 90.5 H 9.5 Z",
          "2": "M 9 9 H 151 V 91 H 9 Z"
        })
      function framePath(w, h, fromMenus) {
        return "M 0 0 H 160 V 100 H 0 Z M 10 10 H 150 V 90 H 10 Z";
      }
      function innerPath(w, h, out) {
        return strokePaths[String(strokeWidth)];
      }
    }
  }

  function frameSpec(frame, fill, stroke, holes) {
    frame.strokeHoles = holes;
    return {
      "kind": "frame",
      "level": "frame",
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
        verify(up * down <= 0 || Math.min(Math.abs(up), Math.abs(down)) <= root.tol, `${what}: ${k} ${values[i][k].toFixed(4)} between ${values[i - 1][k].toFixed(4)} and ${values[i + 1][k].toFixed(4)}`);
      }
    }
  }

  function mustNotData() {
    const rows = [];
    for (const name of ["popout on a pill", "submenu on a popout's side", "popout on a solid bar's inner stroke", "corner merge", "dock on the frame", "pill bar joined to the frame"]) {
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
          "level": "surface",
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

  // ---- a fill's anti-aliased edge, and a non-whole logical size ----

  // A fill's edge half covering a pixel (c_f 0.5) over a lower fill: both
  // captures read the mean of the two fills' values
  function test_aa_edge_over_a_lower_fill() {
    if (root.dpr !== 1)
      skip("scale 1 row");
    const lower = {
      "kind": "rect",
      "level": "bar",
      "x": 10,
      "y": 10,
      "w": 100,
      "h": 60,
      "fill": root.blue
    };
    const upper = {
      "kind": "rect",
      "level": "surface",
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
          "level": "bar",
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
}
