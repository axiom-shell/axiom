pragma ComponentBehavior: Bound
import QtQuick

// The backing window's chrome as one image: its shapes' fills and strokes in
// painter's order (PaintOrder), from two captures (`colorSource`, the colour
// premultiplied, and `alphaSource`, the alpha in grey) the window's chrome
// copies are drawn into. A higher shape's fill replaces what lies under it,
// and each stroke is blended over what is under it, so a surface joined to a
// bar hides the bar's stroke and the two meet without a seam. Premultiplied,
// for the compositor to blend over the blur.
ShaderEffect {
  property var colorSource
  property var alphaSource

  fragmentShader: Qt.resolvedUrl("shaders/chrome-composite.frag.qsb")
}
