pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable

// A copy of each of `shapes`
Item {
  id: copies
  required property var shapes
  // The screen its fills are drawn for (BlurManager.fillOn)
  required property var screen
  // Shapes another window may draw over this one: each not also among
  // `shapes` is among its copies as an eraser (see `erasing`); one in both is
  // drawn
  property var erasers: []
  // What each copy draws: "chrome", its fill (the colour it fills with,
  // opaque) then its stroke over it, at their own alpha, normal blending, so
  // the strokes blend over the fills in painter's order; "outline", its fill
  // and stroke in opaque black, the shape a shadow casts from and is cut by
  property string draws: "chrome"
  // With "chrome": each alpha in grey instead of the colour (the fill an
  // opaque grey at its alpha, the stroke white at its own, erasers black)
  property bool asAlpha: false
  // A copy moved, resized, showed or hid
  signal changed
  anchors.fill: parent

  KeyedModel {
    id: shapeModel
    keys: copies.shapes.concat(copies.erasers).map(shape => shape.uid).filter((key, i, all) => all.indexOf(key) === i)
  }

  Repeater {
    model: shapeModel.model

    // Cut to the shape's clipRect (its window), if it has one
    delegate: Item {
      id: slot
      required property string key
      // Fixed per key; null once it's gone, until its row goes
      readonly property var shape: BlurManager.shapeOf(Number(slot.key))
      readonly property var area: slot.shape?.clipRect ?? null
      // The other window draws this shape now (an eraser not among `shapes`): the slot erases its fill
      // path (opaque black, no stroke, half a level under the shape's) and
      // goes back to drawing the shape when that window gives it up
      readonly property bool erasing: copies.erasers.includes(slot.shape) && !copies.shapes.includes(slot.shape)
      // Its fill's alpha on this screen, as drawn (BlurManager.fillOn)
      readonly property real fillAlpha: BlurManager.fillOn(slot.shape?.color ?? "transparent", copies.screen).a
      // What its copy fills with: black for the outline and an eraser; else
      // its colour premultiplied, or its alpha in grey. A rect's or frame's
      // with no fill alpha (a stroke-only rect) draws none, keeping what
      // lies under it; an attached copy's stays opaque at any alpha, which
      // is what hides a lower stroke at a join
      readonly property color fill: {
        if (copies.draws === "outline" || slot.erasing)
          return "black"; // style-exempt: mask
        if (slot.shape?.kind !== "attached" && slot.fillAlpha <= 0)
          return "transparent";
        return copies.asAlpha ? Qt.rgba(slot.fillAlpha, slot.fillAlpha, slot.fillAlpha, 1) : Tone.over(BlurManager.fillOn(slot.shape?.color ?? "transparent", copies.screen), "black"); // style-exempt: premultiplied
      }
      // Its stroke over the fill, at its own colour and alpha (white at its
      // alpha for the alpha copies); none for an outline or an eraser
      readonly property color stroke: {
        const c = slot.shape?.strokeColor ?? "transparent";
        if (copies.draws !== "chrome" || slot.erasing || c.a <= 0)
          return "transparent";
        return copies.asAlpha ? Qt.rgba(1, 1, 1, c.a) : c; // style-exempt: alpha copy
      }
      // The stroke holes its source leaves open, which its copy cuts (none
      // for the outline copies, whose silhouette stays whole, nor while
      // erasing)
      readonly property var strokeHoles: copies.draws === "chrome" && !slot.erasing ? (slot.shape?.source?.strokeHoles ?? []) : []
      // Painter's order: its shape's level, an eraser's half a level under
      z: slot.erasing ? (slot.shape?.paintLevel ?? 0) - PaintOrder.eraserOffset : (slot.shape?.paintLevel ?? 0)
      x: area ? area.x : 0
      y: area ? area.y : 0
      width: area ? area.width : copies.width
      height: area ? area.height : copies.height
      clip: !!area
      // (read rather than `visible`, which is false inside a hidden layer)
      readonly property bool showing: (slot.shape?.shown ?? false) && !!slot.shape?.source
      visible: slot.showing

      // Where and how big its copy is, as drawn, and in what: on any
      // change the window is nudged to show its last frame
      readonly property string drawn: [mirror.x, mirror.y, mirror.width, mirror.height, slot.showing, (mirror.item as AttachedSurface)?.slid ?? 0, (mirror.item as AttachedSurface)?.shownOpacity ?? 1, (mirror.item as Item)?.opacity ?? 1, slot.fill, slot.stroke, slot.erasing, JSON.stringify(slot.strokeHoles)].join(",")
      // (null while the copies are torn down: their slots can go after them)
      onDrawnChanged: copies?.changed()

      Loader {
        id: mirror
        x: (slot.shape?.x ?? 0) - slot.x
        y: (slot.shape?.y ?? 0) - slot.y
        active: slot.shape !== null
        sourceComponent: slot.shape?.kind === "rect" ? rectMirror : slot.shape?.kind === "frame" ? frameMirror : attachedMirror
      }

      Component {
        id: attachedMirror

        AttachedSurfaceCopy {
          source: slot.shape?.source ?? null
          fillColor: slot.fill
          mirrorStroke: copies.draws === "outline" ? "black" : slot.stroke // style-exempt: mask
          strokeHoles: slot.strokeHoles
        }
      }

      // A rect (a Rectangle source): its fill, and its stroke the way the
      // source draws its border: on itself where it does (a toast card,
      // `border.width` set), else a border-only Rectangle over the fill
      // (an island, the solid bar's inner stroke, the integrated edge
      // menu's border-off line)
      Component {
        id: rectMirror

        Item {
          id: rect
          // (null while its source is going, destroyed before its
          // BlurShape leaves the list, or the window is torn down, as on
          // a reload: it draws nothing then, as AttachedSurfaceCopy)
          readonly property var src: slot.shape?.source ?? null
          visible: src !== null
          width: src?.width ?? 0
          height: src?.height ?? 0
          opacity: slot.shape?.fade ?? 1

          HoledCopy {
            anchors.fill: parent
            holes: slot.strokeHoles
            drawing: rectDrawing
            fillOnly: rectFill
          }

          Component {
            id: rectDrawing

            Rectangle {
              anchors.fill: parent
              topLeftRadius: rect.src?.topLeftRadius ?? 0
              topRightRadius: rect.src?.topRightRadius ?? 0
              bottomLeftRadius: rect.src?.bottomLeftRadius ?? 0
              bottomRightRadius: rect.src?.bottomRightRadius ?? 0
              color: slot.fill
              border.width: slot.stroke.a > 0 ? (rect.src?.border.width ?? 0) : 0
              border.color: slot.stroke

              Rectangle {
                anchors.fill: parent
                visible: slot.stroke.a > 0 && (rect.src?.border.width ?? 0) <= 0
                topLeftRadius: rect.src?.topLeftRadius ?? 0
                topRightRadius: rect.src?.topRightRadius ?? 0
                bottomLeftRadius: rect.src?.bottomLeftRadius ?? 0
                bottomRightRadius: rect.src?.bottomRightRadius ?? 0
                color: "transparent"
                border.width: Appearance.borderWidth
                border.color: slot.stroke
              }
            }
          }

          Component {
            id: rectFill

            Rectangle {
              anchors.fill: parent
              topLeftRadius: rect.src?.topLeftRadius ?? 0
              topRightRadius: rect.src?.topRightRadius ?? 0
              bottomLeftRadius: rect.src?.bottomLeftRadius ?? 0
              bottomRightRadius: rect.src?.bottomRightRadius ?? 0
              color: slot.fill
            }
          }
        }
      }

      // The screen border's frame (RoundedBorders): the screen, less its
      // integrated menus' strips, round the stroke's inner side, and its
      // stroke along the stroke's centre line
      Component {
        id: frameMirror

        Item {
          id: frame
          readonly property var src: slot.shape?.source ?? null
          width: copies.width
          height: copies.height

          HoledCopy {
            anchors.fill: parent
            holes: slot.strokeHoles
            drawing: frameDrawing
            fillOnly: frameFill
          }

          Component {
            id: frameDrawing

            Shape {
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: slot.fill
                fillRule: ShapePath.OddEvenFill
                strokeColor: "transparent"
                strokeWidth: 0

                PathSvg {
                  path: frame.src?.framePath(frame.width, frame.height, true) ?? ""
                }
              }

              ShapePath {
                fillColor: "transparent"
                strokeColor: slot.stroke
                strokeWidth: frame.src?.strokeWidth ?? 0

                PathSvg {
                  path: slot.stroke.a > 0 ? (frame.src?.innerPath(frame.width, frame.height, frame.src.strokeWidth / 2) ?? "") : ""
                }
              }
            }
          }

          Component {
            id: frameFill

            Shape {
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: slot.fill
                fillRule: ShapePath.OddEvenFill
                strokeColor: "transparent"
                strokeWidth: 0

                PathSvg {
                  path: frame.src?.framePath(frame.width, frame.height, true) ?? ""
                }
              }
            }
          }
        }
      }
    }
  }
}
