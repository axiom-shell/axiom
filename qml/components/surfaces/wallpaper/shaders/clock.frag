// A clock hand sweeps around the origin, starting pointing in the
// direction, and leaves the new wallpaper behind it
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 c = (uv - origin) * vec2(aspect, 1.0);
    // How far round from the start the point is: 0 to 1, clockwise (y down)
    float t = fract((atan(c.y, c.x) - angle) / (2.0 * PI) + 1.0);
    finish(mix(fromColor(uv), toColor(uv), reveal(t, 0.03)));
}
