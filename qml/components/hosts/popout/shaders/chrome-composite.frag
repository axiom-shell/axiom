#version 440
// The backing window's chrome (ChromeComposite): its shapes' fills and
// strokes in painter's order, captured twice, in colour (premultiplied rgb)
// and in alpha (grey), as `color` and `alpha`: the pixel is the colour with
// that alpha, premultiplied, at the item's opacity
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D colorSource;
layout(binding = 2) uniform sampler2D alphaSource;

void main() {
    vec2 uv = qt_TexCoord0;
    fragColor = vec4(texture(colorSource, uv).rgb, texture(alphaSource, uv).r) * qt_Opacity;
}
