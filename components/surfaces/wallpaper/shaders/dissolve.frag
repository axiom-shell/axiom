// The new wallpaper burns through in soft patches
void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * vec2(aspect, 1.0);
    float n = noise(p * 6.0) * 0.65 + noise(p * 24.0) * 0.25 + hash(floor(p * 400.0)) * 0.1;
    finish(mix(fromColor(uv), toColor(uv), reveal(n, 0.08)));
}
