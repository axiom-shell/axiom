// A circle of the new wallpaper opens from the origin
void main() {
    vec2 uv = qt_TexCoord0;
    float s = 0.04;
    float t = distanceFromOrigin(uv) / (farthestCorner() + 0.001);
    finish(mix(fromColor(uv), toColor(uv), reveal(t, s)));
}
