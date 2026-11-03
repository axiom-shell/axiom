#version 440
// Shared by every wallpaper transition (prepended by
// scripts/check_shaders.py --build): the two wallpapers, where each sits on
// the screen, and the helpers the transitions build on. At progress 0 a
// transition shows the old wallpaper, at 1 the new one, exactly.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // 0 (the old wallpaper) to 1 (the new one), eased
    float progress;
    // The direction a wipe, slide, wave or blinds moves in (radians)
    float angle;
    // The screen's width / height
    float aspect;
    // Where each image sits on the screen, in screen units: x, y, width,
    // height (a zero width: no image, the background shows)
    vec4 fromRect;
    vec4 toRect;
    // Around an image that doesn't fill the screen (fit, center)
    vec4 background;
    // Where a circle grows from or shrinks to, in screen units
    vec2 origin;
    // A number for the noise, so each run differs
    float seed;
    // How fade, dissolve, pixelate and blur spread: 0 everywhere at once,
    // 1 along the direction, 2 out from the origin (localProgress)
    float sweep;
};

layout(binding = 1) uniform sampler2D fromTex;
layout(binding = 2) uniform sampler2D toTex;

const float PI = 3.14159265;

vec4 fromColor(vec2 uv) {
    if (fromRect.z <= 0.0)
        return background;
    vec2 p = (uv - fromRect.xy) / fromRect.zw;
    if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0)
        return background;
    return texture(fromTex, p);
}

vec4 toColor(vec2 uv) {
    if (toRect.z <= 0.0)
        return background;
    vec2 p = (uv - toRect.xy) / toRect.zw;
    if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0)
        return background;
    return texture(toTex, p);
}

// How much of the new wallpaper shows at a point whose turn comes at t
// (0 first, 1 last), with an edge s wide: 0 everywhere at progress 0, 1
// everywhere at progress 1
float reveal(float t, float s) {
    float e = progress * (1.0 + s);
    return 1.0 - smoothstep(e - s, e, t);
}

// The direction as a unit vector
vec2 direction() {
    return vec2(cos(angle), sin(angle));
}

// Where a point comes along the direction: 0 at the screen's first corner,
// 1 at its last
float along(vec2 uv) {
    vec2 d = direction();
    vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
    float extent = 0.5 * (abs(d.x) * aspect + abs(d.y));
    return dot(c, d) / extent * 0.5 + 0.5;
}

// The distance from the origin, in screen heights, and the farthest corner's
float distanceFromOrigin(vec2 uv) {
    return length((uv - origin) * vec2(aspect, 1.0));
}

float farthestCorner() {
    float d = 0.0;
    d = max(d, distanceFromOrigin(vec2(0.0, 0.0)));
    d = max(d, distanceFromOrigin(vec2(1.0, 0.0)));
    d = max(d, distanceFromOrigin(vec2(0.0, 1.0)));
    d = max(d, distanceFromOrigin(vec2(1.0, 1.0)));
    return d;
}

// This point's own progress for a transition that may sweep: everywhere
// at once (sweep 0), or a wide band moving along the direction (1) or out
// from the origin (2). Still exactly 0 and 1 at progress 0 and 1.
float localProgress(vec2 uv) {
    if (sweep < 0.5)
        return progress;
    float t = sweep < 1.5 ? along(uv) : distanceFromOrigin(uv) / (farthestCorner() + 0.001);
    float w = 0.6;
    return clamp(progress * (1.0 + w) - t * w, 0.0, 1.0);
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21) + seed);
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Smooth noise in [0, 1)
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void finish(vec4 color) {
    fragColor = color * qt_Opacity;
}
