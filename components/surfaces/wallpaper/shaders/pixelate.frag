// The old wallpaper breaks into blocks, which settle into the new one:
// everywhere at once, or sweeping along the direction or out from the origin
void main() {
    vec2 uv = qt_TexCoord0;
    float local = localProgress(uv);
    float size = 0.06 * sin(local * PI);
    vec2 at = uv;
    if (size > 0.002) {
        vec2 cell = vec2(size / aspect, size);
        at = (floor(uv / cell) + 0.5) * cell;
    }
    finish(mix(fromColor(at), toColor(at), smoothstep(0.35, 0.65, local)));
}
