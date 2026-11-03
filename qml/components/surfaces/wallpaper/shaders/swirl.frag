// The old wallpaper twists into the new one around the origin
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 c = (uv - origin) * vec2(aspect, 1.0);
    float radius = farthestCorner();
    float dist = length(c);
    float twist = sin(progress * PI) * 4.0 * max(0.0, 1.0 - dist / radius);
    float s = sin(twist);
    float k = cos(twist);
    vec2 turned = origin + vec2(c.x * k - c.y * s, c.x * s + c.y * k) / vec2(aspect, 1.0);
    finish(mix(fromColor(turned), toColor(turned), smoothstep(0.3, 0.7, progress)));
}
