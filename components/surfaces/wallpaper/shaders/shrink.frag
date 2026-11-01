// The old wallpaper closes into a circle at the origin
void main() {
    vec2 uv = qt_TexCoord0;
    float t = distanceFromOrigin(uv) / (farthestCorner() + 0.001);
    finish(mix(fromColor(uv), toColor(uv), reveal(1.0 - t, 0.04)));
}
