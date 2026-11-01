// The old wallpaper breaks into blocks, which settle into the new one
void main() {
    vec2 uv = qt_TexCoord0;
    float size = 0.06 * sin(progress * PI);
    if (size > 0.002) {
        vec2 cell = vec2(size / aspect, size);
        uv = (floor(uv / cell) + 0.5) * cell;
    }
    finish(mix(fromColor(uv), toColor(uv), smoothstep(0.35, 0.65, progress)));
}
